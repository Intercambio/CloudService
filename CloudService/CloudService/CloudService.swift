//
//  CloudService.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 06.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import Dispatch
import KeyChain

public enum CloudServiceError: Error {
    case internalError
}

extension Notification.Name {
    public static let CloudServiceDidAddAccount = Notification.Name(rawValue: "CloudStore.CloudServiceDidAddAccount")
    public static let CloudServiceDidUdpateAccount = Notification.Name(rawValue: "CloudStore.CloudServiceDidUdpateAccount")
    public static let CloudServiceDidRemoveAccount = Notification.Name(rawValue: "CloudStore.CloudServiceDidRemoveAccount")
    public static let CloudServiceDidChangeAccounts = Notification.Name(rawValue: "CloudStore.CloudServiceDidChangeAccounts")
    public static let CloudServiceDidChangeResources = Notification.Name(rawValue: "CloudStore.CloudServiceDidChangeResources")
}

public let AccountKey = "CloudStore.AccountKey"
public let InsertedOrUpdatedResourcesKey = "CloudStore.InsertedOrUpdatedResourcesKey"
public let DeletedResourcesKey = "CloudStore.DeletedResourcesKey"

public protocol CloudServiceDelegate: class {
    func service(_ service: CloudService, needsPasswordFor account: CloudService.Account, completionHandler: @escaping (String?) -> Void) -> Void
    func serviceDidBeginActivity(_ service: CloudService) -> Void
    func serviceDidEndActivity(_ service: CloudService) -> Void
}

public class CloudService {
    
    public typealias Store = FileStore
    public typealias Resource = Store.Resource
    public typealias Account = Store.Account
    
    public weak var delegate: CloudServiceDelegate?

    private let store: Store
    private let keyChain: KeyChain
    private let queue: DispatchQueue
    
    public init(directory: URL, keyChain: KeyChain) {
        self.store = FileStore(directory: directory)
        self.keyChain = keyChain
        self.queue = DispatchQueue(label: "CloudService")
    }
    
    public func start(completion: ((Error?)->Void)?) {
        queue.async {
            self.store.open { error in
                self.queue.async {
                    do {
                        if error != nil {
                            throw error!
                        }
                        
                        let resumeGroup = DispatchGroup()
                        
                        for account in self.store.accounts {
                            resumeGroup.enter()
                            let manager = self.resourceManager(for: account)
                            manager.resume { error in
                                if error != nil {
                                    NSLog("Failed to resume manager: \(error)")
                                }
                                resumeGroup.leave()
                            }
                        }
                        
                        resumeGroup.notify(queue: self.queue) {
                            completion?(nil)
                        }
                        
                    } catch {
                        completion?(error)
                    }
                }
            }
        }
    }
    
    deinit {
        for (_, manager) in resourceManager {
            manager.invalidateAndCancel()
        }
    }

    // MARK: - Account Management
    
    public var accounts: [Store.Account] {
        return store.accounts
    }
    
    public func addAccount(with url: URL, username: String) throws -> Account {
        let account = try store.addAccount(with: url, username: username)
        let item = KeyChainItem(identifier: account.identifier, invisible: false, options: [:])
        try keyChain.add(item)
        
        let center = NotificationCenter.default
        center.post(name: Notification.Name.CloudServiceDidAddAccount,
                    object: self,
                    userInfo: [AccountKey: account])
        center.post(name: Notification.Name.CloudServiceDidChangeAccounts,
                    object: self)
        
        return account
    }
    
    public func update(_ account: Account, with label: String?) throws -> Account {
        let account = try store.update(account, with: label)
        
        let center = NotificationCenter.default
        center.post(name: Notification.Name.CloudServiceDidUdpateAccount,
                    object: self,
                    userInfo: [AccountKey: account])
        center.post(name: Notification.Name.CloudServiceDidChangeAccounts,
                    object: self)
        
        return account
    }
    
    public func remove(_ account: Account) throws {
        try store.remove(account)
        
        let item = try keyChain.item(with: account.identifier)
        try keyChain.remove(item)
        
        let center = NotificationCenter.default
        center.post(name: Notification.Name.CloudServiceDidRemoveAccount,
                    object: self,
                    userInfo: [AccountKey: account])
        center.post(name: Notification.Name.CloudServiceDidChangeAccounts,
                    object: self)
    }
    
    // MARK: - Resource Management
    
    private var resourceManager: [Account:ResourceManager] = [:]
    
    private func resourceManager(for account: Account) -> ResourceManager {
        if let manager = resourceManager[account] {
            return manager
        } else {
            let manager = ResourceManager(store: store, account: account)
            manager.delegate = self
            resourceManager[account] = manager
            return manager
        }
    }
    
    public func resource(of account: Account, at path: [String]) throws -> Resource? {
        return try store.resource(of: account, at: path)
    }
    
    public func contents(of account: Account, at path: [String]) throws -> [Resource] {
        return try store.contents(of: account, at: path)
    }
    
    public func updateResource(at path: [String], of account: Account, completion: ((Error?) -> Void)?) {
        return queue.async {
            self.beginActivity()
            let manager = self.resourceManager(for: account)
            manager.updateResource(at: path) { error in
                completion?(error)
                self.endActivity()
            }
        }
    }
    
    // MARK: - Manage Credentials
    
    public func password(for account: CloudService.Account) -> String? {
        do {
            return try keyChain.passwordForItem(with: account.identifier)
        } catch {
            return nil
        }
    }
    
    public func setPassword(_ password: String?, for account: CloudService.Account) {
        do {
            try keyChain.setPassword(password, forItemWith: account.identifier)
        } catch {
            NSLog("Failed to update the password: \(error)")
        }
    }
    
    public func requestPassword(for account: CloudService.Account, completion: @escaping (String?) -> Void) -> Void {
        DispatchQueue.main.async {
            if let delegate = self.delegate {
                delegate.service(self, needsPasswordFor: account) { password in
                    self.setPassword(password, for: account)
                    completion(password)
                }
            } else {
                completion(nil)
            }
        }
    }
    
    // MARK: - Activity
    
    private var runningActives: Int = 0 {
        didSet {
            if oldValue != runningActives {
                if oldValue == 0 {
                    DispatchQueue.main.async {
                        self.delegate?.serviceDidBeginActivity(self)
                    }
                } else if runningActives == 0 {
                    DispatchQueue.main.async {
                        self.delegate?.serviceDidEndActivity(self)
                    }
                }
            }
        }
    }
    
    private func beginActivity() {
        runningActives += 1
    }
    
    private func endActivity() {
        runningActives -= 1
    }
}

extension CloudService: ResourceManagerDelegate {
    
    func resourceManager(_ manager: ResourceManager, needsPasswordWith completionHandler: @escaping (String?) -> Void) {
        if let password = password(for: manager.account) {
            completionHandler(password)
        } else {
            requestPassword(for: manager.account) { password in
                completionHandler(password)
            }
        }
    }
    
    func resourceManager(_ manager: ResourceManager, didChange changeSet: Store.ChangeSet) {
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            center.post(name: Notification.Name.CloudServiceDidChangeResources,
                        object: self,
                        userInfo: [InsertedOrUpdatedResourcesKey: changeSet.insertedOrUpdated,
                                   DeletedResourcesKey: changeSet.deleted])
        }
    }
    
    func resourceManager(_ manager: ResourceManager, didStartDownloading resource: Resource) {
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            center.post(name: Notification.Name.CloudServiceDidChangeResources,
                        object: self,
                        userInfo: [InsertedOrUpdatedResourcesKey: [resource],
                                   DeletedResourcesKey: []])
        }
    }
    
    func resourceManager(_ manager: ResourceManager, didFinishDownloading resource: FileStore.Resource) {
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            center.post(name: Notification.Name.CloudServiceDidChangeResources,
                        object: self,
                        userInfo: [InsertedOrUpdatedResourcesKey: [resource],
                                   DeletedResourcesKey: []])
        }
    }
    
    func resourceManager(_ manager: ResourceManager, didFailDownloading resource: FileStore.Resource, error: Error) {
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            center.post(name: Notification.Name.CloudServiceDidChangeResources,
                        object: self,
                        userInfo: [InsertedOrUpdatedResourcesKey: [resource],
                                   DeletedResourcesKey: []])
        }
    }
}

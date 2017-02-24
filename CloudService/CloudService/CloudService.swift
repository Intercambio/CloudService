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
import PureXML

public enum CloudServiceError: Error {
    case internalError
    case invalidResponse
    case unexpectedResponse(statusCode: Int, document: PXDocument?)
}

extension Notification.Name {
    public static let CloudServiceDidAddAccount = Notification.Name(rawValue: "CloudStore.CloudServiceDidAddAccount")
    public static let CloudServiceDidUdpateAccount = Notification.Name(rawValue: "CloudStore.CloudServiceDidUdpateAccount")
    public static let CloudServiceDidRemoveAccount = Notification.Name(rawValue: "CloudStore.CloudServiceDidRemoveAccount")
    public static let CloudServiceDidChangeAccounts = Notification.Name(rawValue: "CloudStore.CloudServiceDidChangeAccounts")
    public static let CloudServiceDidChangeResources = Notification.Name(rawValue: "CloudStore.CloudServiceDidChangeResources")
}

public let AccountIDKey = "CloudStore.AccountIDKey"
public let InsertedOrUpdatedResourcesKey = "CloudStore.InsertedOrUpdatedResourcesKey"
public let DeletedResourcesKey = "CloudStore.DeletedResourcesKey"

public protocol CloudServiceDelegate: class {
    func service(_ service: CloudService, needsPasswordFor account: Account, completionHandler: @escaping (String?) -> Void) -> Void
    func serviceDidBeginActivity(_ service: CloudService) -> Void
    func serviceDidEndActivity(_ service: CloudService) -> Void
}

public class CloudService {
    
    public weak var delegate: CloudServiceDelegate?
    
    private let store: FileStore
    private let keyChain: KeyChain
    private let queue: DispatchQueue
    
    public init(directory: URL, keyChain: KeyChain) {
        self.store = FileStore(directory: directory)
        self.keyChain = keyChain
        self.queue = DispatchQueue(label: "CloudService")
    }
    
    public func start(completion: ((Error?) -> Void)?) {
        queue.async {
            self.store.open { error in
                self.queue.async {
                    do {
                        if error != nil {
                            throw error!
                        }
                        
                        for account in try self.store.allAccounts() {
                            if let manager = self.resourceManager(for: account.identifier) {
                                
                            }
                        }
                        
                        completion?(nil)
                        
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
    
    public func allAccounts() throws -> [Account] {
        return try store.allAccounts()
    }
    
    public func account(with identifier: AccountID) throws -> Account? {
        return try store.account(with: identifier)
    }
    
    public func addAccount(with url: URL, username: String) throws -> Account {
        let account = try store.addAccount(with: url, username: username)
        let item = KeyChainItem(identifier: account.identifier, invisible: false, options: [:])
        try keyChain.add(item)
        
        let center = NotificationCenter.default
        center.post(
            name: Notification.Name.CloudServiceDidAddAccount,
            object: self,
            userInfo: [AccountIDKey: account.identifier]
        )
        center.post(
            name: Notification.Name.CloudServiceDidChangeAccounts,
            object: self
        )
        
        return account
    }
    
    public func update(_ account: Account, with label: String?) throws {
        try store.update(account, with: label)
        
        let center = NotificationCenter.default
        
        center.post(
            name: Notification.Name.CloudServiceDidUdpateAccount,
            object: self,
            userInfo: [AccountIDKey: account.identifier]
        )
        
        center.post(
            name: Notification.Name.CloudServiceDidChangeAccounts,
            object: self
        )
    }
    
    public func remove(_ account: Account) throws {
        try store.remove(account)
        
        let item = try keyChain.item(with: account.identifier)
        try keyChain.remove(item)
        
        let center = NotificationCenter.default
        center.post(
            name: Notification.Name.CloudServiceDidRemoveAccount,
            object: self,
            userInfo: [AccountIDKey: account.identifier]
        )
        center.post(
            name: Notification.Name.CloudServiceDidChangeAccounts,
            object: self
        )
    }
    
    // MARK: - Resource Management
    
    private var resourceManager: [AccountID: ResourceManager] = [:]
    
    private func resourceManager(for accountID: AccountID) -> ResourceManager? {
        if let manager = resourceManager[accountID] {
            return manager
        } else {
            do {
                if let account = try store.account(with: accountID) {
                    let manager = ResourceManager(accountID: account.identifier, baseURL: account.url, store: store)
                    manager.delegate = self
                    resourceManager[accountID] = manager
                    return manager
                } else {
                    return nil
                }
            } catch {
                return nil
            }
        }
    }
    
    public func resource(with resourceID: ResourceID) throws -> Resource? {
        return try store.resource(with: resourceID)
    }
    
    public func content(ofResourceWith resourceID: ResourceID) throws -> [Resource] {
        return try store.content(ofResourceWith: resourceID)
    }
    
    public func updateResource(with resourceID: ResourceID, completion: ((Error?) -> Void)?) {
        return queue.async {
            if let manager = self.resourceManager(for: resourceID.accountID) {
                self.beginActivity()
                manager.update(resourceWith: resourceID) { error in
                    completion?(error)
                    self.endActivity()
                }
            } else {
                completion?(nil)
            }
        }
    }
    
    public func downloadResource(with resourceID: ResourceID) {
        return queue.sync {
        }
    }
    
    public func progressForResource(with resourceID: ResourceID) -> Progress? {
        return queue.sync {
            return nil
        }
    }
    
    // MARK: - Manage Credentials
    
    public func password(for account: Account) -> String? {
        do {
            return try keyChain.passwordForItem(with: account.identifier)
        } catch {
            return nil
        }
    }
    
    public func setPassword(_ password: String?, for account: Account) {
        do {
            try keyChain.setPassword(password, forItemWith: account.identifier)
        } catch {
            NSLog("Failed to update the password: \(error)")
        }
    }
    
    public func requestPassword(for account: Account, completion: @escaping (String?) -> Void) {
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
    
    func resourceManager(_ manager: ResourceManager, needsCredentialWith completionHandler: @escaping (URLCredential?) -> Void) {
        
    }
    
    func resourceManager(_: ResourceManager, didChange changeSet: StoreChangeSet) {
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            center.post(
                name: Notification.Name.CloudServiceDidChangeResources,
                object: self,
                userInfo: [
                    InsertedOrUpdatedResourcesKey: changeSet.insertedOrUpdated,
                    DeletedResourcesKey: changeSet.deleted
                ]
            )
        }
    }
    
}

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
    
    fileprivate let store: FileStore
    private let keyChain: KeyChain
    private let queue: DispatchQueue
    private let sharedContainerIdentifier: String?
    
    public init(directory: URL, keyChain: KeyChain, sharedContainerIdentifier: String? = nil) {
        self.store = FileStore(directory: directory)
        self.keyChain = keyChain
        self.sharedContainerIdentifier = sharedContainerIdentifier
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
                            _ = self.resourceManager(for: account.identifier)
                            _ = self.downloadManager(for: account.identifier)
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
    
    public func resource(with resourceID: ResourceID) throws -> Resource? {
        return try store.resource(with: resourceID)
    }
    
    public func contentOfResource(with resourceID: ResourceID) throws -> [Resource] {
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
        return queue.async {
            if let manager = self.downloadManager(for: resourceID.accountID) {
                manager.download(resourceWith: resourceID)
            }
        }
    }
    
    public func progressForResource(with resourceID: ResourceID) -> Progress? {
        return queue.sync {
            if let manager = self.downloadManager(for: resourceID.accountID) {
                return manager.progress(forResourceWith: resourceID)
            } else {
                return nil
            }
        }
    }
    
    public func deleteFileForResource(with resourceID: ResourceID) throws {
        try store.deleteFile(ofResourceWith: resourceID)
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            center.post(
                name: Notification.Name.CloudServiceDidChangeResources,
                object: self,
                userInfo: [
                    InsertedOrUpdatedResourcesKey: [resourceID],
                    DeletedResourcesKey: []
                ]
            )
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
    
    // MARK: - Manager
    
    private var resourceManager: [AccountID: ResourceManager] = [:]
    private var downloadManager: [AccountID: DownloadManager] = [:]
    
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
    
    private func downloadManager(for accountID: AccountID) -> DownloadManager? {
        if let manager = downloadManager[accountID] {
            return manager
        } else {
            do {
                if let account = try store.account(with: accountID) {
                    let manager = DownloadManager(accountID: account.identifier, baseURL: account.url, store: store, sharedContainerIdentifier: sharedContainerIdentifier)
                    manager.delegate = self
                    downloadManager[accountID] = manager
                    return manager
                } else {
                    return nil
                }
            } catch {
                return nil
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
        do {
            if let account = try store.account(with: manager.accountID) {
                if let password = password(for: account) {
                    let credential = URLCredential(user: account.username, password: password, persistence: .forSession)
                    completionHandler(credential)
                } else {
                    requestPassword(for: account) { password in
                        if let providedPassword = password {
                            let credential = URLCredential(user: account.username, password: providedPassword, persistence: .forSession)
                            completionHandler(credential)
                        } else {
                            completionHandler(nil)
                        }
                    }
                }
            } else {
                completionHandler(nil)
            }
        } catch {
            completionHandler(nil)
        }
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

extension CloudService: DownloadManagerDelegate {
    
    func downloadManager(_ manager: DownloadManager, needsCredentialWith completionHandler: @escaping (URLCredential?) -> Void) {
        do {
            if let account = try store.account(with: manager.accountID) {
                if let password = password(for: account) {
                    let credential = URLCredential(user: account.username, password: password, persistence: .forSession)
                    completionHandler(credential)
                } else {
                    requestPassword(for: account) { password in
                        if let providedPassword = password {
                            let credential = URLCredential(user: account.username, password: providedPassword, persistence: .forSession)
                            completionHandler(credential)
                        } else {
                            completionHandler(nil)
                        }
                    }
                }
            } else {
                completionHandler(nil)
            }
        } catch {
            completionHandler(nil)
        }
    }
    
    func downloadManager(_ manager: DownloadManager, didStartDownloading resourceID: ResourceID) {
        postChangeNotification(for: resourceID)
    }
    
    func downloadManager(_ manager: DownloadManager, didCancelDownloading resourceID: ResourceID) {
        postChangeNotification(for: resourceID)
    }
    
    func downloadManager(_ manager: DownloadManager, didFinishDownloading resourceID: ResourceID) {
        postChangeNotification(for: resourceID)
    }
    
    func downloadManager(_ manager: DownloadManager, didFailDownloading resourceID: ResourceID, error: Error) {
        postChangeNotification(for: resourceID)
    }
    
    private func postChangeNotification(for resourceID: ResourceID) {
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            center.post(
                name: Notification.Name.CloudServiceDidChangeResources,
                object: self,
                userInfo: [
                    InsertedOrUpdatedResourcesKey: [resourceID],
                    DeletedResourcesKey: []
                ]
            )
        }
    }
}

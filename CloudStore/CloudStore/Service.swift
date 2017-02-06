//
//  Service.swift
//  CloudStore
//
//  Created by Tobias Kraentzer on 06.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import Dispatch

public protocol ServiceDelegate: class {
    func service(_ service: Service, needsPasswordFor account: Account, completionHandler: @escaping (String?) -> Void) -> Void
}

public class Service: ResourceManagerDelegate {
    
    public weak var delegate: ServiceDelegate?
    
    public let accountManager: AccountManager
    
    private let store: FileStore
    private let queue: DispatchQueue
    
    public init(directory: URL) {
        self.store = FileStore(directory: directory)
        self.accountManager = AccountManager(store: store)
        self.queue = DispatchQueue(label: "CloudStore.Service")
    }
    
    public func start(completion: ((Error?)->Void)?) {
        queue.async {
            self.store.open(completion: completion)
        }
    }
    
    private var resourceManagers: [Account:ResourceManager] = [:]
    
    public func resourceManager(for account: Account) -> ResourceManager {
        return queue.sync  {
            if let manager = resourceManagers[account] {
                return manager
            } else {
                let manager = ResourceManager(store: store, account: account)
                manager.delegate = self
                resourceManagers[account] = manager
                return manager
            }
        }
    }
    
    // MARK: - ResourceManagerDelegate
    
    func resourceManager(_ manager: ResourceManager, needsPasswordWith completionHandler: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            if let delegate = self.delegate {
                delegate.service(self, needsPasswordFor: manager.account, completionHandler: completionHandler)
            } else {
                completionHandler(nil)
            }
        }
    }
}

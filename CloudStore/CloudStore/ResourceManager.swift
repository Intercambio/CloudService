//
//  ResourceManager.swift
//  CloudStore
//
//  Created by Tobias Kraentzer on 24.01.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import CloudAPI

protocol ResourceManagerDelegate: class {
    func resourceManager(_ manager: ResourceManager, needsPasswordWith completionHandler: @escaping (String?)->Void) -> Void
    func resourceManager(_ manager: ResourceManager, didChange changeset: FileStore.ChangeSet) -> Void
}

class ResourceManager: CloudAPIDelegate {
    
    weak var delegate: ResourceManagerDelegate?
    
    let store: FileStore
    let account: FileStore.Account
    let queue: DispatchQueue
    let api: CloudAPI
    
    init(store: FileStore, account: FileStore.Account) {
        self.store = store
        self.account = account
        self.queue = DispatchQueue(label: "CloudStore.ResourceManager")
        self.api = CloudAPI(identifier: account.url.absoluteString)
        self.api.delegate = self
    }
    
    func updateResource(at path: [String], completion: ((Error?) -> Void)?) {
        let url = account.url.appendingPathComponent(path.joined(separator: "/"))
        self.api.retrieveProperties(of: url) { (result, error) in
            do {
                guard
                    let resources = result?.resources
                    else { throw error ?? CloudServiceError.internalError }
                
                var properties: StoreResourceProperties? = nil
                var content: [String:StoreResourceProperties] = [:]
                
                for resource in resources {
                    guard
                        let resourcePath = resource.url.pathComponents(relativeTo: self.account.url),
                        let etag = resource.etag
                        else { continue }
                    
                    let resourceProperties = FileStoreResourceProperties(isCollection: resource.isCollection, version: etag)
                    
                    if resourcePath == path {
                        properties = resourceProperties
                    } else if resourcePath.starts(with: path)
                        && resourcePath.count == path.count + 1 {
                        let name = resourcePath[path.count]
                        content[name] = resourceProperties
                    }
                }
                
                let changeSet = try self.store.update(resourceAt: path, of: self.account, with: properties, content: content)
                if let delegate = self.delegate {
                    delegate.resourceManager(self, didChange: changeSet)
                }
                
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }
    
    // MARK: - CloudAPIDelegate
    
    func cloudAPI(_ api: CloudAPI,
                  didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard
            let delegate = self.delegate
            else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
        }
        
        delegate.resourceManager(self) { password in
            guard
                let password = password
                else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
            }
            
            let credentials = URLCredential(user: self.account.username,
                                            password: password,
                                            persistence: .forSession)
            completionHandler(.useCredential, credentials)
        }
    }
}

//
//  ResourceManager.swift
//  CloudStore
//
//  Created by Tobias Kraentzer on 24.01.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import CloudAPI

public let InsertedOrUpdatedResourcesKey = "InsertedOrUpdatedResourcesKey"
public let DeletedResourcesKey = "DeletedResourcesKey"

public extension Notification.Name {
    static let ResourceManagerDidChange = Notification.Name(rawValue: "CloudStore.ResourceManagerDidChange")
}

public struct Resource: Equatable, Hashable {
    
    public let account: Account
    
    let storeResource: FileStore.Resource
    init(account: Account, storeResource: FileStore.Resource) {
        self.account = account
        self.storeResource = storeResource
    }
    
    public var path: [String] {
        return storeResource.path
    }
    
    public var isCollection: Bool {
        return storeResource.isCollection
    }
    
    public var dirty: Bool {
        return storeResource.dirty
    }
    
    public static func ==(lhs: Resource, rhs: Resource) -> Bool {
        return lhs.storeResource == rhs.storeResource
    }
    
    public var hashValue: Int {
        return storeResource.hashValue
    }
}

protocol ResourceManagerDelegate: class {
    func resourceManager(_ manager: ResourceManager, needsPasswordWith completionHandler: @escaping (String?)->Void) -> Void
}

public class ResourceManager: CloudAPIDelegate {
    
    weak var delegate: ResourceManagerDelegate?
    
    let store: FileStore
    let account: Account
    let queue: DispatchQueue
    let api: CloudAPI
    
    init(store: FileStore, account: Account) {
        self.store = store
        self.account = account
        self.queue = DispatchQueue(label: "CloudStore.ResourceManager")
        self.api = CloudAPI(identifier: account.url.absoluteString)
        self.api.delegate = self
    }
    
    public func resource(at path: [String]) throws -> Resource? {
        guard
            let storeResource = try store.resource(of: account.storeAccount, at: path)
            else { return nil }
        
        return Resource(account: account, storeResource: storeResource)
    }
    
    public func content(at path: [String]) throws -> [Resource] {
        let content = try store.contents(of: account.storeAccount, at: path)
        
        return content.map { (storeResource) in
            return Resource(account: account, storeResource: storeResource)
        }
    }
    
    public func updateResource(at path: [String], completion: ((Error?) -> Void)?) {
        let url = account.url.appendingPathComponent(path.joined(separator: "/"))
        self.api.retrieveProperties(of: url) { (result, error) in
            
            guard
                let resources = result?.resources
                else { return }
            
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
            
            do {
                
                let changeSet = try self.store.update(resourceAt: path, of: self.account.storeAccount, with: properties, content: content)
                
                let insertedOrUpdated = changeSet.insertedOrUpdated.map { storeResource in
                    return Resource(account: self.account, storeResource: storeResource)
                }
                
                let deleted = changeSet.deleted.map { storeResource in
                    return Resource(account: self.account, storeResource: storeResource)
                }
                
                DispatchQueue.main.async {
                    let center = NotificationCenter.default
                    center.post(name: Notification.Name.ResourceManagerDidChange, object: self,
                                userInfo: [InsertedOrUpdatedResourcesKey: insertedOrUpdated,
                                           DeletedResourcesKey: deleted])
                }
                
            } catch {
                NSLog("Failed ot update store: \(error)")
            }
        }
    }
    
    // MARK: - CloudAPIDelegate
    
    public func cloudAPI(_ api: CloudAPI, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let delegate = self.delegate {
            delegate.resourceManager(self, needsPasswordWith: { (password) in
                if let password = password {
                    completionHandler(.useCredential, URLCredential(user: self.account.username, password: password, persistence: .forSession))
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
            })
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

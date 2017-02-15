//
//  ResourceManager.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 24.01.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

protocol ResourceManagerDelegate: class {
    func resourceManager(_ manager: ResourceManager, needsPasswordWith completionHandler: @escaping (String?)->Void) -> Void
    func resourceManager(_ manager: ResourceManager, didChange changeset: FileStore.ChangeSet) -> Void
    func resourceManager(_ manager: ResourceManager, didStartDownloading resource: FileStore.Resource) -> Void
    func resourceManager(_ manager: ResourceManager, didFailDownloading resource: FileStore.Resource, error: Error) -> Void
    func resourceManager(_ manager: ResourceManager, didFinishDownloading resource: FileStore.Resource) -> Void
}

class ResourceManager: CloudAPIDelegate {
    
    weak var delegate: ResourceManagerDelegate?
    
    let store: FileStore
    let account: FileStore.Account
    let queue: DispatchQueue
    lazy var api: CloudAPI = CloudAPI(identifier: self.account.url.absoluteString, delegate: self)
    
    init(store: FileStore, account: FileStore.Account) {
        self.store = store
        self.account = account
        self.queue = DispatchQueue(label: "CloudStore.ResourceManager")
    }
    
    func resume(completion: ((Error?) -> Void)?) {
        completion?(nil)
    }
    
    func finishTasksAndInvalidate() {
        api.finishTasksAndInvalidate()
    }
    
    func invalidateAndCancel() {
        api.invalidateAndCancel()
    }
    
    func updateResource(at path: [String], completion: ((Error?) -> Void)?) {
        let url = account.url.appendingPathComponent(path.joined(separator: "/"))
        self.api.retrieveProperties(of: url) { (result, error) in
            do {
                if let error = error {
                    switch error {
                    case CloudAPIError.unexpectedResponse(let statusCode, _) where statusCode == 404:
                        let changeSet = try self.removeResource(at: path)
                        if let delegate = self.delegate {
                            delegate.resourceManager(self, didChange: changeSet)
                        }
                    default:
                        throw error
                    }
                } else if let response = result {
                    let changeSet = try self.updateResource(at: path, with: response)
                    if let delegate = self.delegate {
                        delegate.resourceManager(self, didChange: changeSet)
                    }
                } else {
                    throw CloudServiceError.internalError
                }
                
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }
    
    func downloadResource(at path: [String]) {
        let url = account.url.appendingPathComponent(path.joined(separator: "/"))
        self.api.download(url)
    }
    
    private func updateResource(at path: [String], with response: CloudAPIResponse) throws -> FileStore.ChangeSet {
        
        var properties: StoreResourceProperties? = nil
        var content: [String:StoreResourceProperties] = [:]
        
        for resource in response.resources {
            guard
                let resourcePath = resource.url.pathComponents(relativeTo: self.account.url),
                let etag = resource.etag
                else { continue }
            
            let resourceProperties = FileStoreResourceProperties(isCollection: resource.isCollection,
                                                                 version: etag,
                                                                 contentType: resource.contentType,
                                                                 contentLength: resource.contentLength,
                                                                 modified: resource.modified)
            
            if resourcePath == path {
                properties = resourceProperties
            } else if resourcePath.starts(with: path)
                && resourcePath.count == path.count + 1 {
                let name = resourcePath[path.count]
                content[name] = resourceProperties
            }
        }

        return try store.update(resourceAt: path, of: self.account, with: properties, content: content)
    }
    
    private func removeResource(at path: [String]) throws -> FileStore.ChangeSet {
        return try store.update(resourceAt: path, of: account, with: nil)
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
    
    func cloudAPI(_ api: CloudAPI, didFailDownloading url: URL, error: Error) {
        
    }
    
    func cloudAPI(_ api: CloudAPI, didProgressDownloading url: URL, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
    }
    
    func cloudAPI(_ api: CloudAPI, didFinishDownloading url: URL, etag: String, to location: URL) {
        do {
            guard
                let path = url.pathComponents(relativeTo: account.url),
                let resource = try store.resource(of: account, at: path)
                else { return }
            
            do {
                let updatedResource = try store.moveFile(at: location, withVersion: etag, to: resource)
                delegate?.resourceManager(self, didFinishDownloading: updatedResource)
            } catch {
                delegate?.resourceManager(self, didFailDownloading: resource, error: error)
            }
        } catch {
            NSLog("Failed to sotre file: \(error)")
        }
    }
}

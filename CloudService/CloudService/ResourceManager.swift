//
//  ResourceManager.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 24.01.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import PureXML

protocol ResourceManagerDelegate: class {
    func resourceManager(_ manager: ResourceManager, needsCredentialWith completionHandler: @escaping (URLCredential?) -> Void) -> Void
    func resourceManager(_ manager: ResourceManager, didChange changeset: StoreChangeSet) -> Void
}

class ResourceManager: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    
    weak var delegate: ResourceManagerDelegate?
    
    let accountID: AccountID
    let baseURL: URL
    let store: Store
    
    private let operationQueue: OperationQueue
    private let queue: DispatchQueue
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: self.operationQueue)
    }()
    
    private struct PendingUpdate {
        let task: URLSessionDataTask
        var completionHandlers: [((Error?) -> Void)]
    }
    
    private var pendingUpdates: [ResourceID:PendingUpdate] = [:]
    
    init(accountID: AccountID, baseURL: URL, store: Store) {
        self.accountID = accountID
        self.baseURL = baseURL
        self.store = store
        
        queue = DispatchQueue(label: "ResourceManager (\(accountID))")
        operationQueue = OperationQueue()
        operationQueue.underlyingQueue = queue
        
        super.init()
    }
    
    func finishTasksAndInvalidate() {
        queue.async {
            self.session.finishTasksAndInvalidate()
        }
    }
    
    func invalidateAndCancel() {
        queue.async {
            self.session.invalidateAndCancel()
        }
    }
    
    func update(resourceWith resourceID: ResourceID, completion: @escaping ((Error?) -> Void)) {
        queue.async {
            if var pendingUpdate = self.pendingUpdates[resourceID] {
                pendingUpdate.completionHandlers.append(completion)
            } else {
                let resourceURL = self.baseURL.appending(resourceID.path)
                let task = self.session.dataTask(with: resourceURL, completionHandler: { (data, response, error) in
                    self.handleResponse(data: data, response: response, error: error)
                })
                self.pendingUpdates[resourceID] = PendingUpdate(task: task, completionHandlers: [completion])
                task.resume()
            }
        }
    }
    
    // MARK: -
    
    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        guard
            let httpResponse = response as? HTTPURLResponse,
            let url = httpResponse.url,
            let resourceID = makeResourceID(with: url)
            else { return }
        
        if let pendingUpdate = self.pendingUpdates[resourceID] {
            do {
                defer {
                    self.pendingUpdates[resourceID] = nil
                }
                
                if let error = error {
                    throw error
                }
                
                guard
                    let data = data
                    else { throw CloudAPIError.internalError }
                
                switch httpResponse.statusCode {
                case 207:
                    guard
                        let document = PXDocument(data: data)
                        else { throw CloudAPIError.internalError }
                    let result = try CloudAPIResponse(document: document, baseURL: url)
                    let changeSet = try self.updateResource(with: resourceID, using: result)
                    DispatchQueue.global().async {
                        self.delegate?.resourceManager(self, didChange: changeSet)
                    }
                    
                case 404:
                    let changeSet = try self.removeResource(with: resourceID)
                    DispatchQueue.global().async {
                        self.delegate?.resourceManager(self, didChange: changeSet)
                    }
                    
                case let statusCode:
                    let document = PXDocument(data: data)
                    throw CloudAPIError.unexpectedResponse(statusCode: statusCode, document: document)
                }
                
                DispatchQueue.global().async {
                    for handler in pendingUpdate.completionHandlers {
                        handler(nil)
                    }
                }
            } catch {
                DispatchQueue.global().async {
                    for handler in pendingUpdate.completionHandlers {
                        handler(error)
                    }
                }
            }
        }
    }
    
    private func updateResource(with resourceID: ResourceID, using response: CloudAPIResponse) throws -> StoreChangeSet {
        
        var properties: Properties?
        var content: [String: Properties] = [:]
        
        for resource in response.resources {
            guard
                let responseResourceID = makeResourceID(with: resource.url),
                let etag = resource.etag
            else { continue }
            
            let resourceProperties = Properties(
                isCollection: resource.isCollection,
                version: etag,
                contentType: resource.contentType,
                contentLength: resource.contentLength,
                modified: resource.modified
            )
            
            if responseResourceID == resourceID {
                properties = resourceProperties
            } else if responseResourceID.isChild(of: resourceID) {
                let name = responseResourceID.name
                content[name] = resourceProperties
            }
        }
        return try store.update(resourceWith: resourceID, using: properties, content: content)
    }
    
    private func removeResource(with resourceID: ResourceID) throws -> StoreChangeSet {
        return try store.update(resourceWith: resourceID, using: nil)
    }

    private func makeResourceID(with url: URL) -> ResourceID? {
        guard
            let path = url.makePath(relativeTo: baseURL)
            else { return nil }
        return ResourceID(accountID: accountID, path: path)
    }
    
    // MARK: - URLSessionDelegate
    
    public func urlSession(_: URLSession, didBecomeInvalidWithError _: Error?) {
        
    }
    
    // MARK: URLSessionTaskDelegate
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Swift.Void) {
        guard
            session == self.session,
            let url = task.originalRequest?.url,
            let resourceID = makeResourceID(with: url)
            else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
        }
        
        if pendingUpdates[resourceID] == nil {
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            let delegate = self.delegate
            DispatchQueue.global().async {
                delegate?.resourceManager(self, needsCredentialWith: { credential in
                    if credential != nil {
                        completionHandler(.useCredential, credential)
                    } else {
                        completionHandler(.cancelAuthenticationChallenge, nil)
                    }
                })
            }
        }
    }
}

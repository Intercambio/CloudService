//
//  ResourceManager.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 24.01.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

protocol ResourceManagerDelegate: class {
    func resourceManager(_ manager: ResourceManager, needsPasswordWith completionHandler: @escaping (String?) -> Void) -> Void
    func resourceManager(_ manager: ResourceManager, didChange changeset: StoreChangeSet) -> Void
    func resourceManager(_ manager: ResourceManager, didStartDownloading resource: Resource) -> Void
    func resourceManager(_ manager: ResourceManager, didFailDownloading resource: Resource, error: Error) -> Void
    func resourceManager(_ manager: ResourceManager, didFinishDownloading resource: Resource) -> Void
}

class ResourceManager: CloudAPIDelegate {
    
    weak var delegate: ResourceManagerDelegate?
    
    let store: FileStore
    let account: Account
    let queue: DispatchQueue
    lazy var api: CloudAPI = CloudAPI(identifier: self.account.url.absoluteString, delegate: self)
    
    init(store: FileStore, account: Account) {
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
    
    // MARK: Update Resource
    
    func updateResource(at path: Path, completion: ((Error?) -> Void)?) {
        let url = account.url.appending(path)
        self.api.retrieveProperties(of: url) { result, error in
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
    
    private func updateResource(at path: Path, with response: CloudAPIResponse) throws -> StoreChangeSet {
        
        var properties: Properties?
        var content: [String: Properties] = [:]
        
        for resource in response.resources {
            guard
                let resourcePath = resource.url.makePath(relativeTo: self.account.url),
                let etag = resource.etag
            else { continue }
            
            let resourceProperties = Properties(
                isCollection: resource.isCollection,
                version: etag,
                contentType: resource.contentType,
                contentLength: resource.contentLength,
                modified: resource.modified
            )
            
            if resourcePath == path {
                properties = resourceProperties
            } else if resourcePath.components.starts(with: path.components)
                && resourcePath.components.count == path.components.count + 1 {
                let name = resourcePath.components[path.components.count]
                content[name] = resourceProperties
            }
        }
        
        return try store.update(resourceOf: self.account, at: path, with: properties, content: content)
    }
    
    private func removeResource(at path: Path) throws -> StoreChangeSet {
        return try store.update(resourceOf: self.account, at: path, with: nil)
    }
    
    // MARK: Download Resource
    
    func downloadResource(at path: Path) -> Progress {
        return queue.sync {
            let resourceID = ResourceID(accountID: self.account.identifier, path: path)
            let progress = self.makeProgress(for: path)
            
            let url = self.account.url.appending(path)
            self.api.download(url)
            
            do {
                if let resource = try self.store.resource(with: resourceID) {
                    self.delegate?.resourceManager(self, didStartDownloading: resource)
                }
            } catch {
                NSLog("\(error)")
            }
            
            return progress
        }
    }
    
    // MARK: Progress
    
    private var progresByPath: [Path: Progress] = [:]
    
    func progress() -> [Path: Progress] {
        return queue.sync {
            return progresByPath
        }
    }
    
    func progress(for path: Path) -> Progress? {
        return queue.sync {
            return progresByPath[path]
        }
    }
    
    private func makeProgress(for path: Path) -> Progress {
        completeProgress(for: path)
        
        let progress = Progress(totalUnitCount: -1)
        progresByPath[path] = progress
        
        progress.kind = ProgressKind.file
        progress.setUserInfoObject(
            Progress.FileOperationKind.downloading,
            forKey: .fileOperationKindKey
        )
        progress.setUserInfoObject(
            account.url.appending(path),
            forKey: .fileURLKey
        )
        
        return progress
    }
    
    private func updateProgress(for path: Path, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let progress = progresByPath[path] {
            progress.completedUnitCount = totalBytesWritten
            progress.totalUnitCount = totalBytesExpectedToWrite
        }
    }
    
    private func cancelProgress(for path: Path) {
        if let progress = progresByPath[path] {
            progress.cancel()
            progresByPath[path] = nil
        }
    }
    
    private func completeProgress(for path: Path) {
        if let progress = progresByPath[path] {
            progress.completedUnitCount = progress.totalUnitCount
            
            progresByPath[path] = nil
        }
    }
    
    // MARK: - CloudAPIDelegate
    
    func cloudAPI(
        _: CloudAPI,
        didReceive _: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
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
            
            let credentials = URLCredential(
                user: self.account.username,
                password: password,
                persistence: .forSession
            )
            completionHandler(.useCredential, credentials)
        }
    }
    
    func cloudAPI(_: CloudAPI, didFailDownloading url: URL, error _: Error) {
        queue.async {
            guard
                let path = url.makePath(relativeTo: self.account.url)
            else { return }
            
            self.cancelProgress(for: path)
        }
    }
    
    func cloudAPI(_: CloudAPI, didProgressDownloading url: URL, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        queue.async {
            guard
                let path = url.makePath(relativeTo: self.account.url)
            else { return }
            
            self.updateProgress(
                for: path,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
            
        }
    }
    
    func cloudAPI(_: CloudAPI, didFinishDownloading url: URL, etag: String, to location: URL) {
        do {
            guard
                let path = url.makePath(relativeTo: account.url),
                let resource = try store.resource(with: ResourceID(accountID: account.identifier, path: path))
            else { return }
            
            do {
                let updatedResource = try store.moveFile(at: location, withVersion: etag, to: resource)
                delegate?.resourceManager(self, didFinishDownloading: updatedResource)
            } catch {
                delegate?.resourceManager(self, didFailDownloading: resource, error: error)
            }
            
            self.queue.async {
                self.completeProgress(for: path)
            }
            
        } catch {
            NSLog("Failed to sotre file: \(error)")
        }
    }
}

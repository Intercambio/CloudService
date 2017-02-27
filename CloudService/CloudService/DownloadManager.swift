//
//  DownloadManager.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 23.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

protocol DownloadManagerDelegate: class {
    func downloadManager(_ manager: DownloadManager, needsCredentialWith completionHandler: @escaping (URLCredential?) -> Void) -> Void
    func downloadManager(_ manager: DownloadManager, didStartDownloading resourceID: ResourceID) -> Void
    func downloadManager(_ manager: DownloadManager, didCancelDownloading resourceID: ResourceID) -> Void
    func downloadManager(_ manager: DownloadManager, didFailDownloading resourceID: ResourceID, error: Error) -> Void
    func downloadManager(_ manager: DownloadManager, didFinishDownloading resourceID: ResourceID) -> Void
}

class DownloadManager: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    
    weak var delegate: DownloadManagerDelegate?
    
    let accountID: AccountID
    let baseURL: URL
    let store: Store
    
    private let operationQueue: OperationQueue
    private let queue: DispatchQueue
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "download.\(self.accountID)")
        configuration.networkServiceType = .background
        return URLSession(configuration: configuration, delegate: self, delegateQueue: self.operationQueue)
    }()
    
    private struct PendingDownload {
        let task: URLSessionDownloadTask
        let progress: Progress
    }
    
    private var pendingDownloads: [ResourceID:PendingDownload] = [:]
    
    init(accountID: AccountID, baseURL: URL, store: Store) {
        self.accountID = accountID
        self.baseURL = baseURL
        self.store = store
        
        queue = DispatchQueue(label: "DownloadManager (\(accountID))")
        operationQueue = OperationQueue()
        operationQueue.underlyingQueue = queue
        
        super.init()
        
        self.setup()
    }
    
    private func setup() {
        session.getTasksWithCompletionHandler({ (_, _, downloadTasks) in
            for task in downloadTasks {
                guard
                    let url = task.originalRequest?.url,
                    let resourceID = self.makeResourceID(with: url)
                    else { continue }
                
                if self.pendingDownloads[resourceID] == nil {
                    let progress = Progress(totalUnitCount: task.countOfBytesExpectedToReceive)
                    progress.completedUnitCount = task.countOfBytesReceived
                    progress.kind = ProgressKind.file
                    progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
                    progress.setUserInfoObject(url, forKey: .fileURLKey)
                    self.pendingDownloads[resourceID] = PendingDownload(task: task, progress: progress)
                    
                    progress.cancellationHandler = { [weak task] in
                        guard let task = task else { return }
                        task.cancel()
                    }
                    
                    let delegate = self.delegate
                    DispatchQueue.global().async {
                        delegate?.downloadManager(self, didStartDownloading: resourceID)
                    }
                }
            }
        })
    }
    
    func download(resourceWith resourceID: ResourceID) {
        queue.async {
            if self.pendingDownloads[resourceID] == nil {
                let resourceURL = self.baseURL.appending(resourceID.path)
                let task = self.session.downloadTask(with: resourceURL)
                let progress = Progress(totalUnitCount: -1)
                progress.kind = ProgressKind.file
                progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
                progress.setUserInfoObject(resourceURL, forKey: .fileURLKey)
                self.pendingDownloads[resourceID] = PendingDownload(task: task, progress: progress)
                task.resume()
                
                progress.cancellationHandler = { [weak task] in
                    guard let task = task else { return }
                    task.cancel()
                }
                
                let delegate = self.delegate
                DispatchQueue.global().async {
                    delegate?.downloadManager(self, didStartDownloading: resourceID)
                }
            }
        }
    }
    
    func progress(forResourceWith resourceID: ResourceID) -> Progress? {
        return queue.sync {
            return self.pendingDownloads[resourceID]?.progress
        }
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
    
    // MARK: - 
    
    private func makeResourceID(with url: URL) -> ResourceID? {
        guard
            let path = url.makePath(relativeTo: baseURL)
            else { return nil }
        return ResourceID(accountID: accountID, path: path)
    }
    
    // MARK: - URLSessionDelegate
    
    public func urlSession(_: URLSession, didBecomeInvalidWithError _: Error?) {
        
    }
    
    #if os(iOS) || os(tvOS) || os(watchOS)
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    
    }
    #endif
    
    // MARK: URLSessionTaskDelegate
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Swift.Void) {
        guard
            session == self.session,
            let url = task.originalRequest?.url,
            let resourceID = makeResourceID(with: url)
            else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
        }
        
        if pendingDownloads[resourceID] == nil {
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            let delegate = self.delegate
            DispatchQueue.global().async {
                delegate?.downloadManager(self, needsCredentialWith: { credential in
                    if credential != nil {
                        completionHandler(.useCredential, credential)
                    } else {
                        completionHandler(.cancelAuthenticationChallenge, nil)
                    }
                })
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard
            session == self.session,
            let url = task.originalRequest?.url,
            let resourceID = makeResourceID(with: url)
            else { return }
        
        if let pendingDownload = pendingDownloads[resourceID], pendingDownload.task == task {
            let progress = pendingDownload.progress
            pendingDownloads[resourceID] = nil
            
            let delegate = self.delegate
            DispatchQueue.global().async {
                if let downloadError = error {
                    if (downloadError as NSError).domain == NSURLErrorDomain &&
                        (downloadError as NSError).code == NSURLErrorCancelled {
                        delegate?.downloadManager(self, didCancelDownloading: resourceID)
                    } else {
                        delegate?.downloadManager(self, didFailDownloading: resourceID, error: downloadError)
                    }
                } else {
                    progress.completedUnitCount = progress.totalUnitCount
                    delegate?.downloadManager(self, didFinishDownloading: resourceID)
                }
            }
        }
    }
    
    // MARK: URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard
            session == self.session,
            let url = downloadTask.originalRequest?.url,
            let resourceID = makeResourceID(with: url)
            else { return }
        
        if let pendingDownload = pendingDownloads[resourceID], pendingDownload.task == downloadTask {
            let progress = pendingDownload.progress
            progress.completedUnitCount = totalBytesWritten
            progress.totalUnitCount = totalBytesExpectedToWrite
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard
            session == self.session,
            let url = downloadTask.originalRequest?.url,
            let resourceID = makeResourceID(with: url),
            let response = downloadTask.response as? HTTPURLResponse
            else { return }
        
        if let pendingDownload = pendingDownloads[resourceID], pendingDownload.task == downloadTask {
            do {
                switch response.statusCode {
                case 200:
                    if let etag = response.allHeaderFields["Etag"] as? String {
                        try store.moveFile(at: location, withVersion: etag, toResourceWith: resourceID)
                    } else {
                        throw CloudServiceError.invalidResponse
                    }
                default:
                    throw CloudServiceError.unexpectedResponse(statusCode: response.statusCode, document: nil)
                }
            } catch {
                let delegate = self.delegate
                DispatchQueue.global().async {
                    delegate?.downloadManager(self, didFailDownloading: resourceID, error: error)
                }
            }
        }
    }
}

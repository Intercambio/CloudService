//
//  CloudAPI.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 04.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import PureXML

public enum CloudAPIError: Error {
    case internalError
    case invalidResponse
    case unexpectedResponse(statusCode: Int, document: PXDocument?)
}

public enum CloudAPIRequestDepth: String {
    case resource = "0"
    case collection = "1"
    case tree = "infinity"
}

public protocol CloudAPIDelegate: class {
    func cloudAPI(_ api: CloudAPI, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) -> Void
    func cloudAPI(_ api: CloudAPI, didProgressDownloading url: URL, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) -> Void
    func cloudAPI(_ api: CloudAPI, didFinishDownloading url: URL, etag: String, to location: URL) -> Void
    func cloudAPI(_ api: CloudAPI, didFailDownloading url: URL, error: Error) -> Void
}

public class CloudAPI: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {
    
    private(set) public var delegate: CloudAPIDelegate?
    public let identifier: String
    
    private let operationQueue: OperationQueue
    private let queue: DispatchQueue
    
    private lazy var downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "download.\(self.identifier)")
        configuration.networkServiceType = .background
        return URLSession(configuration: configuration, delegate: self, delegateQueue: self.operationQueue)
    }()
    
    private lazy var dataSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: self.operationQueue)
    }()
    
    private var pendingDownloads: Set<URL> = Set<URL>()
    
    public init(identifier: String, delegate: CloudAPIDelegate?) {
        queue = DispatchQueue(label: "CloudAPI (\(identifier))")
        operationQueue = OperationQueue()
        operationQueue.underlyingQueue = queue
        
        self.delegate = delegate
        self.identifier = identifier
        
        super.init()
        
        downloadSession.getAllTasks { tasks in
            for task in tasks {
                if let downloadTask = task as? URLSessionDownloadTask {
                    guard
                        let url = downloadTask.originalRequest?.url
                    else { continue }
                    self.pendingDownloads.insert(url)
                    let totalBytesWritten = downloadTask.countOfBytesReceived
                    let totalBytesExpectedToWrite = downloadTask.countOfBytesExpectedToReceive
                    self.delegate?.cloudAPI(
                        self,
                        didProgressDownloading: url,
                        totalBytesWritten: totalBytesWritten,
                        totalBytesExpectedToWrite: totalBytesExpectedToWrite
                    )
                }
            }
        }
    }
    
    public func finishTasksAndInvalidate() {
        dataSession.finishTasksAndInvalidate()
        downloadSession.finishTasksAndInvalidate()
    }
    
    public func invalidateAndCancel() {
        dataSession.invalidateAndCancel()
        downloadSession.invalidateAndCancel()
    }
    
    private var pendingPropertiesRequests: [URL: [(CloudAPIResponse?, Error?) -> Void]] = [:]
    
    public func retrieveProperties(of url: URL, with depth: CloudAPIRequestDepth = .collection, completion: @escaping ((CloudAPIResponse?, Error?) -> Void)) {
        queue.async {
            let standardizedURL = url.standardized
            if var completionHandlers = self.pendingPropertiesRequests[standardizedURL] {
                completionHandlers.append(completion)
            } else {
                let completionHandlers = [completion]
                self.pendingPropertiesRequests[standardizedURL] = completionHandlers
                let request = URLRequest.makePropFindRequest(for: standardizedURL, with: depth)
                let task = self.dataSession.dataTask(with: request) { [weak self] data, response, error in
                    guard
                        let this = self
                    else { return }
                    this.queue.async {
                        let handlers = this.pendingPropertiesRequests[standardizedURL] ?? []
                        this.pendingPropertiesRequests[standardizedURL] = nil
                        do {
                            guard
                                let data = data,
                                let httpResponse = response as? HTTPURLResponse
                            else { throw error ?? CloudAPIError.internalError }
                            switch httpResponse.statusCode {
                            case 207:
                                guard
                                    let document = PXDocument(data: data)
                                else { throw CloudAPIError.internalError }
                                let result = try CloudAPIResponse(document: document, baseURL: standardizedURL)
                                for handler in handlers {
                                    handler(result, nil)
                                }
                            case let statusCode:
                                let document = PXDocument(data: data)
                                throw CloudAPIError.unexpectedResponse(statusCode: statusCode, document: document)
                            }
                        } catch {
                            for handler in handlers {
                                handler(nil, error)
                            }
                        }
                    }
                }
                task.resume()
            }
        }
    }
    
    public func download(_ url: URL) {
        queue.sync {
            let standardizedURL = url.standardized
            if self.pendingDownloads.contains(standardizedURL) {
                return
            } else {
                self.pendingDownloads.insert(standardizedURL)
                let taks = self.downloadSession.downloadTask(with: standardizedURL)
                taks.resume()
            }
        }
    }
    
    // MARK: - URLSessionDelegate
    
    public func urlSession(_: URLSession, didBecomeInvalidWithError _: Error?) {
        delegate = nil
    }
    
    #if os(iOS) || os(tvOS) || os(watchOS)
        public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            if session == downloadSession {
                NSLog("Background URL Session did finish Events -- \(session)")
            }
        }
    #endif
    
    // MARK: URLSessionTaskDelegate
    
    public func urlSession(_ session: URLSession, task _: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Swift.Void) {
        if let delegate = self.delegate {
            delegate.cloudAPI(self, didReceive: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.rejectProtectionSpace, nil)
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if session == downloadSession {
            guard
                let url = task.originalRequest?.url
            else { return }
            
            pendingDownloads.remove(url)
            if let donwloadError = error {
                delegate?.cloudAPI(self, didFailDownloading: url, error: donwloadError)
            }
        }
    }
    
    // MARK: URLSessionDownloadDelegate
    
    public func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard
            let url = downloadTask.originalRequest?.url,
            let delegate = self.delegate
        else { return }
        
        delegate.cloudAPI(self, didProgressDownloading: url, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
    }
    
    public func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard
            let url = downloadTask.originalRequest?.url,
            let delegate = self.delegate,
            let response = downloadTask.response as? HTTPURLResponse
        else { return }
        
        switch response.statusCode {
        case 200:
            let etag = response.allHeaderFields["Etag"] as? String
            delegate.cloudAPI(self, didFinishDownloading: url, etag: etag ?? "", to: location)
        default:
            let error = CloudAPIError.unexpectedResponse(statusCode: response.statusCode, document: nil)
            delegate.cloudAPI(self, didFailDownloading: url, error: error)
        }
    }
}

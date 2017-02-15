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
    
    public weak var delegate: CloudAPIDelegate?
    
    public let identifier: String
    
    private let operationQueue: OperationQueue
    private let queue: DispatchQueue

    private lazy var downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "download.\(self.identifier)")
        return URLSession(configuration: configuration, delegate: self, delegateQueue: self.operationQueue)
    }()
    
    private lazy var dataSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: self.operationQueue)
    }()
    
    public init(identifier: String) {
        self.identifier = identifier
        
        queue = DispatchQueue(label: "CloudAPI (\(identifier))")
        operationQueue = OperationQueue()
        operationQueue.underlyingQueue = queue
        
        super.init()
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
            if var completionHandlers = self.pendingPropertiesRequests[url] {
                completionHandlers.append(completion)
            } else {
                let completionHandlers = [completion]
                self.pendingPropertiesRequests[url] = completionHandlers
                let request = URLRequest.makePropFindRequest(for: url, with: depth)
                let task = self.dataSession.dataTask(with: request) { [weak self] data, response, error in
                    guard
                        let this = self
                    else { return }
                    this.queue.async {
                        let handlers = this.pendingPropertiesRequests[url] ?? []
                        this.pendingPropertiesRequests[url] = nil
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
                                let result = try CloudAPIResponse(document: document, baseURL: url)
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
    
    private var pendingDownloads: [URL] = []
    
    public func download(_ url: URL) {
        queue.sync {
            if self.pendingDownloads.contains(url) {
                return
            } else {
                self.pendingDownloads.append(url)
                let taks = self.downloadSession.downloadTask(with: url)
                taks.resume()
            }
        }
    }
    
    // MARK: - URLSessionDelegate
    
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        
    }
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let delegate = self.delegate {
            delegate.cloudAPI(self, didReceive: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.rejectProtectionSpace, nil)
        }
    }
    
    // MARK: URLSessionTaskDelegate
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if session == downloadSession {
            guard
                let url = task.originalRequest?.url
                else { return }
            
            if let index = pendingDownloads.index(of: url) {
                pendingDownloads.remove(at: index)
                if let donwloadError = error {
                    delegate?.cloudAPI(self, didFailDownloading: url, error: donwloadError)
                }
            }
        }
    }
    
    // MARK: URLSessionDownloadDelegate
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard
            let url = downloadTask.originalRequest?.url,
            let delegate = self.delegate
            else { return }
        
        delegate.cloudAPI(self, didProgressDownloading: url, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
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

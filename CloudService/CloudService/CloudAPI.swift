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
}

public enum CloudAPIHTTPError: Error {
    case status(code: Int, document: PXDocument?)
}

public enum CloudAPIRequestDepth: String {
    case resource = "0"
    case collection = "1"
    case tree = "infinity"
}

public protocol CloudAPIDelegate: class {
    func cloudAPI(
        _ api: CloudAPI,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Void
}

public class CloudAPI: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    
    public weak var delegate: CloudAPIDelegate?
    
    public let identifier: String
    
    private let operationQueue: OperationQueue
    private let queue: DispatchQueue
    
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
                                throw CloudAPIHTTPError.status(code: statusCode, document: document)
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
    
    // MARK: - URLSessionTaskDelegate
    
    public func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Swift.Void
    ) {
        if let delegate = self.delegate {
            delegate.cloudAPI(self, didReceive: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.rejectProtectionSpace, nil)
        }
    }
    
}

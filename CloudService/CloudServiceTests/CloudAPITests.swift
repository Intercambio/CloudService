//
//  CloudAPITests.swift
//  CloudServiceTests
//
//  Created by Tobias Kräntzer on 04.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
@testable import CloudService

class CloudAPITests: XCTestCase, CloudAPIDelegate {
    
    func testAPI() {
        
        let api = CloudAPI(identifier: "123")
        api.delegate = self
        
        let expectation = self.expectation(description: "Response")
        api.retrieveProperties(of: URL(string: "https://cloud.example.org/webdav/")!) { _, _ in
            
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    // MARK: - CloudAPIDelegate
    
    func cloudAPI(_: CloudAPI, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.host == "cloud.example.org" {
            completionHandler(.useCredential, URLCredential(user: "username", password: "password", persistence: .forSession))
        } else {
            completionHandler(.rejectProtectionSpace, nil)
        }
    }
    
    
    func cloudAPI(_ api: CloudAPI, didFinishDownloading url: URL, etag: String, to location: URL) {
        
    }
}

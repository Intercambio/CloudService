//
//  CloudAPITests.swift
//  CloudServiceTests
//
//  Created by Tobias Kräntzer on 04.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
import OHHTTPStubs
@testable import CloudService

class CloudAPITests: XCTestCase, CloudAPIDelegate {
    
    override func tearDown() {
        OHHTTPStubs.removeAllStubs()
        super.tearDown()
    }
    
    // MARK: Tests
    
    func testRetrieveProperties() {
        stub(condition: isHost("example.com") && isPath("/webdav")) { _ in
            let stubPath = OHPathForFile("propfind.xml", type(of: self))
            return fixture(filePath: stubPath!, status: 207, headers: ["Content-Type":"application/xml"])
        }
        
        let api = CloudAPI(identifier: "123")
        api.delegate = self
        
        let expectation = self.expectation(description: "Response")
        api.retrieveProperties(of: URL(string: "https://example.com/webdav/")!) { response, error in
            XCTAssertNil(error)
            XCTAssertEqual(response?.resources.count, 6)
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

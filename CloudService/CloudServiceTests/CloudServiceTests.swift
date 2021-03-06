//
//  CloudServiceTests.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 07.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
import CloudService
import KeyChain

class CloudServiceTests: TestCase, CloudServiceDelegate {
    
    var service: CloudService?
    
    override func setUp() {
        super.setUp()
        
        guard
            let directory = self.directory
        else { XCTFail(); return }
        
        let keyChain = KeyChain(serviceName: "CloudServiceTests")
        let service = CloudService(directory: directory, keyChain: keyChain, bundleIdentifier: "test")
        service.delegate = self
        
        let expectation = self.expectation(description: "Start")
        service.start { error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)
        
        self.service = service
    }
    
    override func tearDown() {
        self.service = nil
        super.tearDown()
    }
    
    // MARK: Tests
    
    func test() {
        
    }
    
    // MARK: - CloudServiceDelegate
    
    func service(_: CloudService, needsPasswordFor _: Account, completionHandler _: @escaping (String?) -> Void) {
        
    }
    
    func serviceDidBeginActivity(_: CloudService) {
        
    }
    
    func serviceDidEndActivity(_: CloudService) {
        
    }
}

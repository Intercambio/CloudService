//
//  CloudServiceTests.swift
//  CloudStore
//
//  Created by Tobias Kraentzer on 07.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
import CloudStore

class CloudServiceTests: TestCase, CloudServiceDelegate {
    
    var service: CloudService?
    
    override func setUp() {
        super.setUp()
        
        guard
            let directory = self.directory
            else { XCTFail(); return }
        
        let service = CloudService(directory: directory)
        service.delegate = self
        
        let expectation = self.expectation(description: "Start")
        service.start { (error) in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)
        
        self.service = service
    }
    
    // MARK: - CloudServiceDelegate
    
    func service<Account: StoreAccount>(_ service: CloudService, needsPasswordFor account: Account, completionHandler: @escaping (String?) -> Void) {
        
    }
}

//
//  ResourceManagerTests.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 13.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
import OHHTTPStubs
@testable import CloudService

class ResourceManagerTests: TestCase, ResourceManagerDelegate {
    
    var store: Store?
    var account: Account?
    
    override func setUp() {
        super.setUp()
        
        guard
            let directory = self.directory
        else { XCTFail(); return }
        
        let store = FileStore(directory: directory)
        
        let expectation = self.expectation(description: "Open DB")
        store.open { error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)
        
        let baseURL = URL(string: "https://example.com/")!
        
        self.account = try! store.addAccount(with: baseURL, username: "test")
        self.store = store
    }
    
    override func tearDown() {
        OHHTTPStubs.removeAllStubs()
        super.tearDown()
    }
    
    func testUpdateExistingResource() {
        guard
            let store = self.store,
            let account = self.account
            else { XCTFail(); return }
        
        stub(condition: isHost("example.com") && isPath("/test/existing")) { _ in
            let stubPath = OHPathForFile("resource_manager_test_existing.xml", type(of: self))
            return fixture(filePath: stubPath!, status: 207, headers: ["Content-Type": "application/xml"])
        }
        
        let resourceID = ResourceID(accountID: account.identifier, components: ["test", "existing"])
        
        let manager = ResourceManager(accountID: account.identifier,
                                      baseURL: account.url,
                                      store: store)
        manager.delegate = self
        
        let update = expectation(description: "Update")
        
        manager.update(resourceWith: resourceID) { error in
            XCTAssertNil(error)
            update.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)
        
        let resource = try! store.resource(with: resourceID)
        XCTAssertNotNil(resource)
        XCTAssertEqual(resource?.properties.version, "587b4e820026f")
    }
    
    func testUpdateRemovedResource() {
        guard
            let store = self.store,
            let account = self.account
            else { XCTFail(); return }
        
        stub(condition: isHost("example.com") && isPath("/test/removed")) { _ in
            let stubPath = OHPathForFile("resource_manager_test_removed.xml", type(of: self))
            return fixture(filePath: stubPath!, status: 404, headers: ["Content-Type": "application/xml"])
        }
        
        let resourceID = ResourceID(accountID: account.identifier, components: ["test", "removed"])
        
        let manager = ResourceManager(accountID: account.identifier,
                                      baseURL: account.url,
                                      store: store)
        manager.delegate = self
        
        let update = expectation(description: "Update")
        
        manager.update(resourceWith: resourceID) { error in
            XCTAssertNil(error)
            update.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)
        
        let resource = try! store.resource(with: resourceID)
        XCTAssertNil(resource)
    }
    
    // MARK: ResourceManagerDelegate
    
    func resourceManager(_ manager: ResourceManager, needsCredentialWith completionHandler: @escaping (URLCredential?) -> Void) {
        let center = NotificationCenter.default
        center.post(name: Notification.Name(rawValue: "ResourceManagerDelegate.resourceManager(_:needsCredentialWith:)"),
                    object: self,
                    userInfo: ["manager": manager, "completionHandler": completionHandler])
    }
    
    func resourceManager(_ manager: ResourceManager, didChange changeset: StoreChangeSet) {
        let center = NotificationCenter.default
        center.post(name: Notification.Name(rawValue: "ResourceManagerDelegate.resourceManager(_:didChange:)"),
                    object: self,
                    userInfo: ["manager": manager, "changeset": changeset])
    }
}

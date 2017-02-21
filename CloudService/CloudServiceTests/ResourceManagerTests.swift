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
    
    var store: FileStore?
    
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
        
        self.store = store
    }
    
    override func tearDown() {
        OHHTTPStubs.removeAllStubs()
        super.tearDown()
    }
    
    func testUpdateExistingResource() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            
            stub(condition: isHost("example.com") && isPath("/test/existing")) { _ in
                let stubPath = OHPathForFile("resource_manager_test_existing.xml", type(of: self))
                return fixture(filePath: stubPath!, status: 207, headers: ["Content-Type": "application/xml"])
            }
            
            let account = try store.addAccount(with: URL(string: "http://example.com")!, username: "romeo")
            let resourceManager = ResourceManager(store: store, account: account)
            resourceManager.delegate = self
            
            let update = expectation(description: "Update")
            resourceManager.updateResource(at: Path(components: ["test", "existing"])) { error in
                XCTAssertNil(error)
                update.fulfill()
            }
            waitForExpectations(timeout: 1.0, handler: nil)
            
            if let changeset = self.changeset {
                XCTAssertTrue(changeset.insertedOrUpdated.count > 0)
            } else {
                XCTFail()
            }
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testUpdateRemovedResource() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            stub(condition: isHost("example.com") && isPath("/test/removed")) { _ in
                let stubPath = OHPathForFile("resource_manager_test_removed.xml", type(of: self))
                return fixture(filePath: stubPath!, status: 404, headers: ["Content-Type": "application/xml"])
            }
            
            let account = try store.addAccount(with: URL(string: "http://example.com")!, username: "romeo")
            let resourceManager = ResourceManager(store: store, account: account)
            resourceManager.delegate = self
            
            let path = Path(components: ["test", "removed"])
            let properties = Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil)
            _ = try store.update(resourceOf: account, at: path, with: properties)
            
            let update = expectation(description: "Update")
            resourceManager.updateResource(at: path) { error in
                XCTAssertNil(error)
                update.fulfill()
            }
            waitForExpectations(timeout: 1.0, handler: nil)
            
            if let changeset = self.changeset {
                XCTAssertTrue(changeset.deleted.count > 0)
            } else {
                XCTFail()
            }
            
            let resource = try store.resource(of: account, at: path)
            XCTAssertNil(resource)
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testDownload() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let account = try store.addAccount(with: URL(string: "http://example.com")!, username: "romeo")
            let resourceManager = ResourceManager(store: store, account: account)
            resourceManager.delegate = self
            
            let path = Path(components: ["test", "file"])
            let properties = Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil)
            _ = try store.update(resourceOf: account, at: path, with: properties)
            
            expectation(forNotification: "Test.ResourceManager.startDownloadingResourceAt", object: resourceManager, handler: nil)
            expectation(forNotification: "Test.ResourceManager.finishDownloadingResourceAt", object: resourceManager, handler: nil)
            
            resourceManager.downloadResource(at: path)
            
            waitForExpectations(timeout: 1.0, handler: nil)
            
            let resource = try store.resource(of: account, at: path)
            XCTAssertNil(resource)
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    // MARK: ResourceManagerDelegate
    
    var changeset: StoreChangeSet?
    
    func resourceManager(_: ResourceManager, didChange changeset: StoreChangeSet) {
        self.changeset = changeset
    }
    
    func resourceManager(_: ResourceManager, needsPasswordWith completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
    
    func resourceManager(_: ResourceManager, didStartDownloading _: Resource) {
        
    }
    
    func resourceManager(_: ResourceManager, didFinishDownloading _: Resource) {
        
    }
    
    func resourceManager(_: ResourceManager, didFailDownloading _: Resource, error _: Error) {
        
    }
}

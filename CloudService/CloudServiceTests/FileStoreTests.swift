//
//  FileStoreTests.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 02.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
@testable import CloudService

class FileStoreTests: TestCase {
    
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
    
    func testManageAccounts() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account = try store.addAccount(with: url, username: "romeo")
            XCTAssertEqual(account.url, url)
            
            XCTAssertTrue(try store.allAccounts().contains(account))
            
            try store.update(account, with: "Foo Bar")
            XCTAssertEqual(try store.account(with: account.identifier)?.label, "Foo Bar")
            
            try store.remove(account)
            XCTAssertFalse(try store.allAccounts().contains(account))
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testRemoveAccount() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account = try store.addAccount(with: url, username: "romeo")
            XCTAssertEqual(account.url, url)
            
            let path = Path(components: ["a"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
            
            _ = try store.update(resourceWith: resourceID, using: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            
            try store.remove(account)
            XCTAssertNil(try store.resource(with: resourceID))
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testInsertResource() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let date = Date()
            let url = URL(string: "https://example.com/api/")!
            let account: Account = try store.addAccount(with: url, username: "romeo")
            let path = Path(components: ["a", "b", "c"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
            
            let properties = Properties(isCollection: false, version: "123", contentType: "application/pdf", contentLength: 55555, modified: date)
            let changeSet = try store.update(resourceWith: resourceID, using: properties)
            
            XCTAssertEqual(changeSet.insertedOrUpdated.count, 1)
            
            let resource = try store.resource(with: resourceID)
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.resourceID.path, path)
                XCTAssertEqual(resource.properties.version, "123")
                XCTAssertFalse(resource.properties.isCollection)
                XCTAssertFalse(resource.dirty)
                XCTAssertNotNil(resource.updated)
                
                XCTAssertEqual(resource.properties.contentType, "application/pdf")
                XCTAssertEqual(resource.properties.contentLength, 55555)
                XCTAssertEqual(round(resource.properties.modified?.timeIntervalSinceNow ?? -100), round(date.timeIntervalSinceNow))
                
                let content = try store.content(ofResourceWith: resourceID.parent!)
                XCTAssertEqual(content, [resource])
            }
            
            var parentResourceID = resourceID.parent
            while parentResourceID != nil {
                let contents = try store.content(ofResourceWith: parentResourceID!)
                XCTAssertEqual(contents.count, 1)
                
                let resource = try store.resource(with: parentResourceID!)
                XCTAssertNotNil(resource)
                if let resource = resource {
                    XCTAssertTrue(resource.dirty)
                    XCTAssertTrue(resource.properties.isCollection)
                }
                parentResourceID = parentResourceID!.parent
            }
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testInsertCollection() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account: Account = try store.addAccount(with: url, username: "romeo")
            let path = Path(components: ["a", "b", "c"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
            
            let properties = Properties(isCollection: true, version: "123", contentType: nil, contentLength: nil, modified: nil)
            let content = [
                "1": Properties(isCollection: true, version: "a", contentType: nil, contentLength: nil, modified: nil),
                "2": Properties(isCollection: false, version: "b", contentType: nil, contentLength: nil, modified: nil),
                "3": Properties(isCollection: false, version: "c", contentType: nil, contentLength: nil, modified: nil)
            ]
            _ = try store.update(resourceWith: resourceID, using: properties, content: content)
            
            XCTAssertNotNil(try store.resource(with: resourceID.appending("1")))
            XCTAssertNotNil(try store.resource(with: resourceID.appending("2")))
            XCTAssertNotNil(try store.resource(with: resourceID.appending("3")))
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testUpdateCollection() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account = try store.addAccount(with: url, username: "romeo")
            let path = Path(components: ["a", "b", "c"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
   
            _ = try store.update(resourceWith: resourceID.appending(["x", "y"]), using: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceWith: resourceID.appending(["3", "x"]), using: Properties(isCollection: true, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceWith: resourceID.appending(["3"]), using: Properties(isCollection: true, version: "123", contentType: nil, contentLength: nil, modified: nil))
            
            let properties = Properties(isCollection: true, version: "123", contentType: nil, contentLength: nil, modified: nil)
            let content = [
                "1": Properties(isCollection: true, version: "a", contentType: nil, contentLength: nil, modified: nil),
                "2": Properties(isCollection: false, version: "b", contentType: nil, contentLength: nil, modified: nil),
                "3": Properties(isCollection: false, version: "c", contentType: nil, contentLength: nil, modified: nil)
            ]
            let changeSet = try store.update(resourceWith: resourceID, using: properties, content: content)
            
            XCTAssertEqual(changeSet.insertedOrUpdated.count, 4)
            XCTAssertEqual(changeSet.deleted.count, 1)
            
            let resource = try store.resource(with: resourceID)
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.resourceID.path, path)
                XCTAssertEqual(resource.properties.version, "123")
                XCTAssertTrue(resource.properties.isCollection)
                XCTAssertFalse(resource.dirty)
            }
            
            if let resource = try store.resource(with: resourceID.appending("1")) {
                XCTAssertEqual(resource.resourceID.path, Path(components: ["a", "b", "c", "1"]))
                XCTAssertEqual(resource.properties.version, "a")
                XCTAssertTrue(resource.properties.isCollection)
                XCTAssertTrue(resource.dirty)
            } else {
                XCTFail()
            }
            
            if let resource = try store.resource(with: resourceID.appending("2")) {
                XCTAssertEqual(resource.resourceID.path, Path(components: ["a", "b", "c", "2"]))
                XCTAssertEqual(resource.properties.version, "b")
                XCTAssertFalse(resource.properties.isCollection)
                XCTAssertFalse(resource.dirty)
            } else {
                XCTFail()
            }
            
            XCTAssertEqual(try store.content(ofResourceWith: resourceID).count, 3)
            XCTAssertNil(try store.resource(with: resourceID.appending("x")))
            XCTAssertNil(try store.resource(with: resourceID.appending(["x", "y"])))
            XCTAssertNil(try store.resource(with: resourceID.appending(["3", "x"])))
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testUpdateCollectionResource() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account = try store.addAccount(with: url, username: "romeo")
            let path = Path(components: ["a", "b"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
            
            _ = try store.update(resourceWith: resourceID.appending("c"), using: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceWith: resourceID, using: Properties(isCollection: true, version: "567", contentType: nil, contentLength: nil, modified: nil))
            
            let resource = try store.resource(with: resourceID)
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.resourceID.path, path)
                XCTAssertEqual(resource.properties.version, "567")
                XCTAssertTrue(resource.properties.isCollection)
                XCTAssertFalse(resource.dirty)
            }
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testUpdateResource() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account = try store.addAccount(with: url, username: "romeo")
            let path = Path(components: ["a", "b", "c"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
             
            _ = try store.update(resourceWith: resourceID, using: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceWith: resourceID.parent!, using: Properties(isCollection: true, version: "567", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceWith: resourceID, using: Properties(isCollection: false, version: "888", contentType: nil, contentLength: nil, modified: nil))
            
            let resource = try store.resource(with: resourceID)
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.resourceID.path, path)
                XCTAssertEqual(resource.properties.version, "888")
                XCTAssertFalse(resource.properties.isCollection)
                XCTAssertFalse(resource.dirty)
                
                let content = try store.content(ofResourceWith: resourceID.parent!)
                XCTAssertEqual(content, [resource])
            }
            
            var parentResourceID = resourceID.parent
            while parentResourceID != nil {
                let contents = try store.content(ofResourceWith: parentResourceID!)
                XCTAssertEqual(contents.count, 1)
                
                let resource = try store.resource(with: parentResourceID!)
                XCTAssertNotNil(resource)
                if let resource = resource {
                    XCTAssertTrue(resource.dirty)
                    XCTAssertTrue(resource.properties.isCollection)
                }
                parentResourceID = parentResourceID!.parent
            }
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testChangeResourceType() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account = try store.addAccount(with: url, username: "romeo")
            let path = Path(components: ["a", "b", "c"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
            
            _ = try store.update(resourceWith: resourceID, using: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceWith: resourceID.parent!, using: Properties(isCollection: false, version: "567", contentType: nil, contentLength: nil, modified: nil))
            
            let resource = try store.resource(with: resourceID)
            XCTAssertNil(resource)
            
            let content = try store.content(ofResourceWith: resourceID.parent!)
            XCTAssertEqual(content, [])
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testRemoveResource() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account = try store.addAccount(with: url, username: "romeo")
            let path = Path(components: ["a", "b", "c"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
            
            _ = try store.update(resourceWith: resourceID, using: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            let changeSet = try store.update(resourceWith: resourceID.parent!, using: nil)
            
            XCTAssertEqual(changeSet.insertedOrUpdated.count, 0)
            XCTAssertEqual(changeSet.deleted.count, 1)
            
            XCTAssertNil(try store.resource(with: resourceID))
            XCTAssertNil(try store.resource(with: resourceID.parent!))
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testMoveFile() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account = try store.addAccount(with: url, username: "romeo")
            let path = Path(components: ["a", "b", "c"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
            
            let properties = Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil)
            let fileURL = Bundle(for: FileStoreTests.self).url(forResource: "file", withExtension: "txt")!
            let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let tempFileURL = tempDirectory.appendingPathComponent("file.txt")
            try? FileManager.default.copyItem(at: fileURL, to: tempFileURL)
            
            _ = try store.update(resourceWith: resourceID, using: properties)
            
            try store.moveFile(at: tempFileURL, withVersion: "123", toResourceWith: resourceID)
            
            var resource = try store.resource(with: resourceID)
            XCTAssertEqual(resource!.fileState, .valid)
            XCTAssertNotNil(resource!.fileURL)
            if let url = resource!.fileURL {
                let content = try String(contentsOf: url)
                XCTAssertTrue(content.contains("Lorem ipsum dolor sit amet"))
            }
            
            _ = try store.update(resourceWith: resourceID, using: Properties(isCollection: false, version: "345", contentType: nil, contentLength: nil, modified: nil))
            resource = try store.resource(with: resourceID)
            
            XCTAssertEqual(resource!.fileState, .outdated)
            XCTAssertNotNil(resource!.fileURL)

            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testMoveFileVersionMissmatch() {
        guard
            let store = self.store
        else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account = try store.addAccount(with: url, username: "romeo")
            let path = Path(components: ["a", "b", "c"])
            let resourceID = ResourceID(accountID: account.identifier, path: path)
            
            let properties = Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil)
            let fileURL = Bundle(for: FileStoreTests.self).url(forResource: "file", withExtension: "txt")!
            let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let tempFileURL = tempDirectory.appendingPathComponent("file.txt")
            try? FileManager.default.copyItem(at: fileURL, to: tempFileURL)
            
            _ = try store.update(resourceWith: resourceID, using: properties)
            
            if let resource = try store.resource(with: resourceID) {
                XCTAssertThrowsError(try store.moveFile(at: tempFileURL, withVersion: "345", toResourceWith: resource.resourceID))
                XCTAssertEqual(resource.fileState, .none)
            } else {
                XCTFail()
            }
            
        } catch {
            XCTFail("\(error)")
        }
    }
}

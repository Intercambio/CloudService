//
//  FileStoreTests.swift
//  CloudStore
//
//  Created by Tobias Kräntzer on 02.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
@testable import CloudStore

class FileStoreTests: TestCase {
    
    var store: FileStore?
    
    override func setUp() {
        super.setUp()
        
        guard
            let directory = self.directory
            else { XCTFail(); return }
        
        let store = FileStore(directory: directory)
        
        let expectation = self.expectation(description: "Open DB")
        store.open { (error) in
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
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")
            XCTAssertEqual(account.url, url)
            
            XCTAssertTrue(store.accounts.contains(account))
            
            let updatedAccount = try store.update(account, with: "Foo Bar")
            XCTAssertEqual(updatedAccount.label, "Foo Bar")
            
            try store.remove(account)
            XCTAssertFalse(store.accounts.contains(account))
            
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
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")
            XCTAssertEqual(account.url, url)
            
            _ = try store.update(resourceAt: ["a"], of: account, with: Properties(isCollection: false, version: "123"))
            
            try store.remove(account)
            XCTAssertNil(try store.resource(of: account, at: ["a"]))
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testRemoteURL() {
        guard
            let store = self.store
            else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")
            
            let path = ["a", "b", "c"]
            let properties = Properties(isCollection: false, version: "123")
            let _ = try store.update(resourceAt: path, of: account, with: properties)
            
            let resource = try store.resource(of: account, at: path)
            XCTAssertNotNil(resource)
            if let resource = resource {
                let remoteURL = resource.remoteURL
                XCTAssertEqual(remoteURL.absoluteString, "https://example.com/api/a/b/c")
            }
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testInsertResource() {
        guard
            let store = self.store
            else { XCTFail(); return }
        
        do {
            let url = URL(string: "https://example.com/api/")!
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")
            
            let path = ["a", "b", "c"]
            let properties = Properties(isCollection: false, version: "123")
            let changeSet = try store.update(resourceAt: path, of: account, with: properties)
            
            XCTAssertEqual(changeSet.insertedOrUpdated.count, 1)
            
            let resource = try store.resource(of: account, at: path)
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.path, path)
                XCTAssertEqual(resource.version, "123")
                XCTAssertFalse(resource.isCollection)
                XCTAssertFalse(resource.dirty)
            
                var parentPath = path
                parentPath.removeLast()
                let content = try store.contents(of: account, at: parentPath)
                XCTAssertEqual(content, [resource])
            }
            
            var parentPath = path
            
            while parentPath.count > 0 {
                parentPath.removeLast()
                
                let contents = try store.contents(of: account, at: parentPath)
                XCTAssertEqual(contents.count, 1)
                
                let resource = try store.resource(of: account, at: parentPath)
                XCTAssertNotNil(resource)
                if let resource = resource {
                    XCTAssertTrue(resource.dirty)
                    XCTAssertTrue(resource.isCollection)
                }
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
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")
            
            let path = ["a", "b", "c"]
            let properties = Properties(isCollection: true, version: "123")
            let content = [
                "1": Properties(isCollection: true, version: "a"),
                "2": Properties(isCollection: false, version: "b"),
                "3": Properties(isCollection: false, version: "c")
            ]
            _ = try store.update(resourceAt: path, of: account, with: properties, content: content)
            
            XCTAssertNotNil(try store.resource(of: account, at: ["a", "b", "c", "1"]))
            XCTAssertNotNil(try store.resource(of: account, at: ["a", "b", "c", "2"]))
            XCTAssertNotNil(try store.resource(of: account, at: ["a", "b", "c", "3"]))
            
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
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")
            
            _ = try store.update(resourceAt: ["a", "b", "c", "x", "y"], of: account, with: Properties(isCollection: false, version: "123"))
            _ = try store.update(resourceAt: ["a", "b", "c", "3", "x"], of: account, with: Properties(isCollection: true, version: "123"))
            _ = try store.update(resourceAt: ["a", "b", "c", "3"], of: account, with: Properties(isCollection: true, version: "123"))
            
            let path = ["a", "b", "c"]
            let properties = Properties(isCollection: true, version: "123")
            let content = [
                "1": Properties(isCollection: true, version: "a"),
                "2": Properties(isCollection: false, version: "b"),
                "3": Properties(isCollection: false, version: "c")
            ]
            let changeSet = try store.update(resourceAt: path, of: account, with: properties, content: content)

            XCTAssertEqual(changeSet.insertedOrUpdated.count, 4)
            XCTAssertEqual(changeSet.deleted.count, 1)
            
            let resource = try store.resource(of: account, at: path)
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.path, path)
                XCTAssertEqual(resource.version, "123")
                XCTAssertTrue(resource.isCollection)
                XCTAssertFalse(resource.dirty)
            }
            
            if let resource = try store.resource(of: account, at: ["a", "b", "c", "1"]) {
                XCTAssertEqual(resource.path, ["a", "b", "c", "1"])
                XCTAssertEqual(resource.version, "a")
                XCTAssertTrue(resource.isCollection)
                XCTAssertTrue(resource.dirty)
            } else {
                XCTFail()
            }
            
            if let resource = try store.resource(of: account, at: ["a", "b", "c", "2"]) {
                XCTAssertEqual(resource.path, ["a", "b", "c", "2"])
                XCTAssertEqual(resource.version, "b")
                XCTAssertFalse(resource.isCollection)
                XCTAssertFalse(resource.dirty)
            } else {
                XCTFail()
            }

            XCTAssertEqual(try store.contents(of: account, at: path).count, 3)
            XCTAssertNil(try store.resource(of: account, at: ["a", "b", "c", "x"]))
            XCTAssertNil(try store.resource(of: account, at: ["a", "b", "c", "x", "y"]))
            XCTAssertNil(try store.resource(of: account, at: ["a", "b", "c", "3", "x"]))
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
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")
            
            _ = try store.update(resourceAt: ["a", "b", "c"], of: account, with: Properties(isCollection: false, version: "123"))
            _ = try store.update(resourceAt: ["a", "b"], of: account, with: Properties(isCollection: true, version: "567"))
            
            let resource = try store.resource(of: account, at: ["a", "b"])
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.path, ["a", "b"])
                XCTAssertEqual(resource.version, "567")
                XCTAssertTrue(resource.isCollection)
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
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")
            
            _ = try store.update(resourceAt: ["a", "b", "c"], of: account, with: Properties(isCollection: false, version: "123"))
            _ = try store.update(resourceAt: ["a", "b"], of: account, with: Properties(isCollection: true, version: "567"))
            _ = try store.update(resourceAt: ["a", "b", "c"], of: account, with: Properties(isCollection: false, version: "888"))
            
            let resource = try store.resource(of: account, at: ["a", "b", "c"])
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.path, ["a", "b", "c"])
                XCTAssertEqual(resource.version, "888")
                XCTAssertFalse(resource.isCollection)
                XCTAssertFalse(resource.dirty)
                
                let content = try store.contents(of: account, at: ["a", "b"])
                XCTAssertEqual(content, [resource])
            }
            
            var parentPath = ["a", "b", "c"]
            while parentPath.count > 0 {
                parentPath.removeLast()
                
                let contents = try store.contents(of: account, at: parentPath)
                XCTAssertEqual(contents.count, 1)
                
                let resource = try store.resource(of: account, at: parentPath)
                XCTAssertNotNil(resource)
                if let resource = resource {
                    XCTAssertTrue(resource.dirty)
                    XCTAssertTrue(resource.isCollection)
                }
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
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")
            
            _ = try store.update(resourceAt: ["a", "b", "c"], of: account, with: Properties(isCollection: false, version: "123"))
            _ = try store.update(resourceAt: ["a", "b"], of: account, with: Properties(isCollection: false, version: "567"))
            
            let resource = try store.resource(of: account, at: ["a", "b", "c"])
            XCTAssertNil(resource)
            
            let content = try store.contents(of: account, at: ["a", "b"])
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
            let account: FileStore.Account = try store.addAccount(with: url, username: "romeo")

            _ = try store.update(resourceAt: ["a", "b", "c"], of: account, with: Properties(isCollection: false, version: "123"))
            let changeSet = try store.update(resourceAt: ["a", "b"], of: account, with: nil)
            
            XCTAssertEqual(changeSet.insertedOrUpdated.count, 0)
            XCTAssertEqual(changeSet.deleted.count, 1)
            
            XCTAssertNil(try store.resource(of: account, at: ["a", "b", "c"]))
            XCTAssertNil(try store.resource(of: account, at: ["a", "b"]))
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    struct Properties: StoreResourceProperties {
        let isCollection: Bool
        let version: String
    }
    
}

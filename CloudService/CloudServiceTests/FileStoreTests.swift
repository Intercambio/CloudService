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
            let account = try store.addAccount(with: url, username: "romeo")
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
            let account = try store.addAccount(with: url, username: "romeo")
            XCTAssertEqual(account.url, url)
            
            _ = try store.update(resourceOf: account, at: Path(components: ["a"]), with: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            
            try store.remove(account)
            XCTAssertNil(try store.resource(of: account, at: Path(components: ["a"])))
            
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
            let account = try store.addAccount(with: url, username: "romeo")
            
            let path = Path(components: ["a", "b", "c"])
            let properties = Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil)
            let _ = try store.update(resourceOf: account, at: path, with: properties)
            
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
            let date = Date()
            let url = URL(string: "https://example.com/api/")!
            let account: Account = try store.addAccount(with: url, username: "romeo")
            
            let path = Path(components: ["a", "b", "c"])
            let properties = Properties(isCollection: false, version: "123", contentType: "application/pdf", contentLength: 55555, modified: date)
            let changeSet = try store.update(resourceOf: account, at: path, with: properties)
            
            XCTAssertEqual(changeSet.insertedOrUpdated.count, 1)
            
            let resource = try store.resource(of: account, at: path)
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.path, path)
                XCTAssertEqual(resource.properties.version, "123")
                XCTAssertFalse(resource.properties.isCollection)
                XCTAssertFalse(resource.dirty)
                XCTAssertNotNil(resource.updated)
                
                XCTAssertEqual(resource.properties.contentType, "application/pdf")
                XCTAssertEqual(resource.properties.contentLength, 55555)
                XCTAssertEqual(round(resource.properties.modified?.timeIntervalSinceNow ?? -100), round(date.timeIntervalSinceNow))
                
                let content = try store.contents(of: account, at: path.parent!)
                XCTAssertEqual(content, [resource])
            }
            
            var parentPath = path.parent
            
            while parentPath != nil {
                let contents = try store.contents(of: account, at: parentPath!)
                XCTAssertEqual(contents.count, 1)
                
                let resource = try store.resource(of: account, at: parentPath!)
                XCTAssertNotNil(resource)
                if let resource = resource {
                    XCTAssertTrue(resource.dirty)
                    XCTAssertTrue(resource.properties.isCollection)
                }
                parentPath = parentPath!.parent
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
            let properties = Properties(isCollection: true, version: "123", contentType: nil, contentLength: nil, modified: nil)
            let content = [
                "1": Properties(isCollection: true, version: "a", contentType: nil, contentLength: nil, modified: nil),
                "2": Properties(isCollection: false, version: "b", contentType: nil, contentLength: nil, modified: nil),
                "3": Properties(isCollection: false, version: "c", contentType: nil, contentLength: nil, modified: nil)
            ]
            _ = try store.update(resourceOf: account, at: path, with: properties, content: content)
            
            XCTAssertNotNil(try store.resource(of: account, at: Path(components: ["a", "b", "c", "1"])))
            XCTAssertNotNil(try store.resource(of: account, at: Path(components: ["a", "b", "c", "2"])))
            XCTAssertNotNil(try store.resource(of: account, at: Path(components: ["a", "b", "c", "3"])))
            
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
            
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b", "c", "x", "y"]), with: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b", "c", "3", "x"]), with: Properties(isCollection: true, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b", "c", "3"]), with: Properties(isCollection: true, version: "123", contentType: nil, contentLength: nil, modified: nil))
            
            let path = Path(components: ["a", "b", "c"])
            let properties = Properties(isCollection: true, version: "123", contentType: nil, contentLength: nil, modified: nil)
            let content = [
                "1": Properties(isCollection: true, version: "a", contentType: nil, contentLength: nil, modified: nil),
                "2": Properties(isCollection: false, version: "b", contentType: nil, contentLength: nil, modified: nil),
                "3": Properties(isCollection: false, version: "c", contentType: nil, contentLength: nil, modified: nil)
            ]
            let changeSet = try store.update(resourceOf: account, at: path, with: properties, content: content)

            XCTAssertEqual(changeSet.insertedOrUpdated.count, 4)
            XCTAssertEqual(changeSet.deleted.count, 1)
            
            let resource = try store.resource(of: account, at: path)
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.path, path)
                XCTAssertEqual(resource.properties.version, "123")
                XCTAssertTrue(resource.properties.isCollection)
                XCTAssertFalse(resource.dirty)
            }
            
            if let resource = try store.resource(of: account, at: Path(components: ["a", "b", "c", "1"])) {
                XCTAssertEqual(resource.path, Path(components: ["a", "b", "c", "1"]))
                XCTAssertEqual(resource.properties.version, "a")
                XCTAssertTrue(resource.properties.isCollection)
                XCTAssertTrue(resource.dirty)
            } else {
                XCTFail()
            }
            
            if let resource = try store.resource(of: account, at: Path(components: ["a", "b", "c", "2"])) {
                XCTAssertEqual(resource.path, Path(components: ["a", "b", "c", "2"]))
                XCTAssertEqual(resource.properties.version, "b")
                XCTAssertFalse(resource.properties.isCollection)
                XCTAssertFalse(resource.dirty)
            } else {
                XCTFail()
            }

            XCTAssertEqual(try store.contents(of: account, at: path).count, 3)
            XCTAssertNil(try store.resource(of: account, at: Path(components: ["a", "b", "c", "x"])))
            XCTAssertNil(try store.resource(of: account, at: Path(components: ["a", "b", "c", "x", "y"])))
            XCTAssertNil(try store.resource(of: account, at: Path(components: ["a", "b", "c", "3", "x"])))
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
            
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b", "c"]), with: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b"]), with: Properties(isCollection: true, version: "567", contentType: nil, contentLength: nil, modified: nil))
            
            let resource = try store.resource(of: account, at: Path(components: ["a", "b"]))
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.path, Path(components: ["a", "b"]))
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
            
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b", "c"]), with: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b"]), with: Properties(isCollection: true, version: "567", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b", "c"]), with: Properties(isCollection: false, version: "888", contentType: nil, contentLength: nil, modified: nil))
            
            let resource = try store.resource(of: account, at: Path(components: ["a", "b", "c"]))
            XCTAssertNotNil(resource)
            if let resource = resource {
                XCTAssertEqual(resource.path, Path(components: ["a", "b", "c"]))
                XCTAssertEqual(resource.properties.version, "888")
                XCTAssertFalse(resource.properties.isCollection)
                XCTAssertFalse(resource.dirty)
                
                let content = try store.contents(of: account, at: Path(components: ["a", "b"]))
                XCTAssertEqual(content, [resource])
            }
            
            var parentPath = Path(components: ["a", "b", "c"]).parent
            while parentPath != nil {
                let contents = try store.contents(of: account, at: parentPath!)
                XCTAssertEqual(contents.count, 1)
                
                let resource = try store.resource(of: account, at: parentPath!)
                XCTAssertNotNil(resource)
                if let resource = resource {
                    XCTAssertTrue(resource.dirty)
                    XCTAssertTrue(resource.properties.isCollection)
                }
                parentPath = parentPath!.parent
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
            
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b", "c"]), with: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b"]), with: Properties(isCollection: false, version: "567", contentType: nil, contentLength: nil, modified: nil))
            
            let resource = try store.resource(of: account, at: Path(components: ["a", "b", "c"]))
            XCTAssertNil(resource)
            
            let content = try store.contents(of: account, at: Path(components: ["a", "b"]))
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

            _ = try store.update(resourceOf: account, at: Path(components: ["a", "b", "c"]), with: Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil))
            let changeSet = try store.update(resourceOf: account, at: Path(components: ["a", "b"]), with: nil)
            
            XCTAssertEqual(changeSet.insertedOrUpdated.count, 0)
            XCTAssertEqual(changeSet.deleted.count, 1)
            
            XCTAssertNil(try store.resource(of: account, at: Path(components: ["a", "b", "c"])))
            XCTAssertNil(try store.resource(of: account, at: Path(components: ["a", "b"])))
            
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
            let properties = Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil)
            let fileURL = Bundle(for: FileStoreTests.self).url(forResource: "file", withExtension: "txt")!
            let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let tempFileURL = tempDirectory.appendingPathComponent("file.txt")
            try? FileManager.default.copyItem(at: fileURL, to: tempFileURL)
            
            _ = try store.update(resourceOf: account, at: path, with: properties)
            
            if var resource = try store.resource(of: account, at: path) {
                resource = try store.moveFile(at: tempFileURL, withVersion: "123", to: resource)
                XCTAssertEqual(resource.fileState, .valid)
                XCTAssertNotNil(resource.fileURL)
                if let url = resource.fileURL {
                    let content = try String(contentsOf: url)
                    XCTAssertTrue(content.contains("Lorem ipsum dolor sit amet"))
                }
                
                let properties = Properties(isCollection: false, version: "345", contentType: nil, contentLength: nil, modified: nil)
                _ = try store.update(resourceOf: account, at: path, with: properties)
                resource = try store.resource(of: account, at: path)!
                
                XCTAssertEqual(resource.fileState, .outdated)
                XCTAssertNotNil(resource.fileURL)
                
            } else {
                XCTFail()
            }

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
            let properties = Properties(isCollection: false, version: "123", contentType: nil, contentLength: nil, modified: nil)
            let fileURL = Bundle(for: FileStoreTests.self).url(forResource: "file", withExtension: "txt")!
            let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let tempFileURL = tempDirectory.appendingPathComponent("file.txt")
            try? FileManager.default.copyItem(at: fileURL, to: tempFileURL)
            
            _ = try store.update(resourceOf: account, at: path, with: properties)
            
            if let resource = try store.resource(of: account, at: path) {
                XCTAssertThrowsError(try store.moveFile(at: tempFileURL, withVersion: "345", to: resource))
                XCTAssertEqual(resource.fileState, .none)
            } else {
                XCTFail()
            }
            
        } catch {
            XCTFail("\(error)")
        }
    }
}

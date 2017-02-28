//
//  DownloadManagerTests.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 24.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
@testable import CloudService

class DownloadManagerTests: CloudServiceTests, DownloadManagerDelegate {
    
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
        
        let baseURL = URL(string: "https://tobias-kraentzer.de/test/")!
        
        self.account = try! store.addAccount(with: baseURL, username: "test")
        self.store = store
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testStartDownload() {
        guard
            let store = self.store,
            let account = self.account
            else { XCTFail(); return }
        
        let resourceID = ResourceID(accountID: account.identifier, components: ["file.txt"])
        let properties = Properties(isCollection: false, version: "\"14823ab-250-5488e34064d9b\"", contentType: nil, contentLength: nil, modified: nil)
        _ = try! store.update(resourceWith: resourceID, using: properties)
        
        let manager = DownloadManager(accountID: account.identifier,
                                      baseURL: account.url,
                                      store: store)
        manager.delegate = self
        
        expectation(forNotification: "DownloadManagerDelegate.downloadManager(_:needsCredentialWith:)", object: self) { (notification) -> Bool in
            guard
                let manager = notification.userInfo?["manager"] as? DownloadManager,
                let completionHandler = notification.userInfo?["completionHandler"] as? (URLCredential?) -> Void,
                manager.accountID == account.identifier
                else { return false }
            
            let credentials = URLCredential(user: "test", password: "test123", persistence: .forSession)
            completionHandler(credentials)
            
            return true
        }
        
        expectation(forNotification: "DownloadManagerDelegate.downloadManager(_:didStartDownloading:)", object: self) { notification in
            guard
                let manager = notification.userInfo?["manager"] as? DownloadManager
                else { return false }
            return manager.accountID == account.identifier
        }
        
        expectation(forNotification: "DownloadManagerDelegate.downloadManager(_:didFinishDownloading:)", object: self) { notification in
            guard
                let manager = notification.userInfo?["manager"] as? DownloadManager
                else { return false }
            return manager.accountID == account.identifier
        }
        
        manager.download(resourceWith: resourceID)
        
        let progress = manager.progress(forResourceWith: resourceID)
        XCTAssertNotNil(progress)
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func testDownloadWithError() {
        guard
            let store = self.store,
            let account = self.account
            else { XCTFail(); return }
        
        let resourceID = ResourceID(accountID: account.identifier, components: ["xxx-file.txt"])

        let manager = DownloadManager(accountID: account.identifier,
                                      baseURL: account.url,
                                      store: store)
        manager.delegate = self
        
        expectation(forNotification: "DownloadManagerDelegate.downloadManager(_:needsCredentialWith:)", object: self) { (notification) -> Bool in
            guard
                let manager = notification.userInfo?["manager"] as? DownloadManager,
                let completionHandler = notification.userInfo?["completionHandler"] as? (URLCredential?) -> Void,
                manager.accountID == account.identifier
                else { return false }
            
            let credentials = URLCredential(user: "test", password: "test123", persistence: .forSession)
            completionHandler(credentials)
            
            return true
        }
        
        expectation(forNotification: "DownloadManagerDelegate.downloadManager(_:didStartDownloading:)", object: self) { notification in
            guard
                let manager = notification.userInfo?["manager"] as? DownloadManager
                else { return false }
            return manager.accountID == account.identifier
        }
        
        expectation(forNotification: "DownloadManagerDelegate.downloadManager(_:didFailDownloading:error:)", object: self) { notification in
            guard
                let manager = notification.userInfo?["manager"] as? DownloadManager
                else { return false }
            return manager.accountID == account.identifier
        }
        
        manager.download(resourceWith: resourceID)
        
        let progress = manager.progress(forResourceWith: resourceID)
        XCTAssertNotNil(progress)
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    // MARK: - DownloadManagerDelegate
    
    func downloadManager(_ manager: DownloadManager, needsCredentialWith completionHandler: @escaping (URLCredential?) -> Void) {
        let center = NotificationCenter.default
        center.post(name: Notification.Name(rawValue: "DownloadManagerDelegate.downloadManager(_:needsCredentialWith:)"),
                    object: self,
                    userInfo: ["manager": manager, "completionHandler": completionHandler])
    }
    
    func downloadManager(_ manager: DownloadManager, didStartDownloading resourceID: ResourceID) {
        let center = NotificationCenter.default
        center.post(name: Notification.Name(rawValue: "DownloadManagerDelegate.downloadManager(_:didStartDownloading:)"),
                    object: self,
                    userInfo: ["manager": manager, "resourceID": resourceID])
    }
    
    func downloadManager(_ manager: DownloadManager, didCancelDownloading resourceID: ResourceID) {
        let center = NotificationCenter.default
        center.post(name: Notification.Name(rawValue: "DownloadManagerDelegate.downloadManager(_:didCancelDownloading:)"),
                    object: self,
                    userInfo: ["manager": manager, "resourceID": resourceID])
    }
    
    func downloadManager(_ manager: DownloadManager, didFinishDownloading resourceID: ResourceID) {
        let center = NotificationCenter.default
        center.post(name: Notification.Name(rawValue: "DownloadManagerDelegate.downloadManager(_:didFinishDownloading:)"),
                    object: self,
                    userInfo: ["manager": manager, "resourceID": resourceID])
    }
    
    func downloadManager(_ manager: DownloadManager, didFailDownloading resourceID: ResourceID, error: Error) {
        let center = NotificationCenter.default
        center.post(name: Notification.Name(rawValue: "DownloadManagerDelegate.downloadManager(_:didFailDownloading:error:)"),
                    object: self,
                    userInfo: ["manager": manager, "resourceID": resourceID, "error": error])
    }
}

//
//  FileStore.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 02.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import SQLite

enum FileStoreError: Error {
    case notSetup
    case versionMismatch
    case resourceDoesNotExist
    case internalError
}

class FileStore: NSObject, Store, FileManagerDelegate {
    
    private let queue: DispatchQueue = DispatchQueue(label: "FileStore")
    
    private let fileCoordinator: NSFileCoordinator = NSFileCoordinator()
    private let fileManager: FileManager = FileManager()
    
    let directory: URL
    init(directory: URL) {
        self.directory = directory
        super.init()
        fileManager.delegate = self
    }
    
    private var db: SQLite.Connection?
    
    // MARK: - Open & Close
    
    func open(completion: ((Error?) -> Void)?) {
        queue.async {
            do {
                try self.open()
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }
    
    func close() {
        queue.sync {
            self.db = nil
        }
    }
    
    private func open() throws {
        let setup = FileStoreSchema(directory: directory)
        db = try setup.create()
    }
    
    // MARK: - Store
    
    // MARK: Accounts
    
    func allAccounts() throws -> [Account] {
        return try queue.sync {
            return try self.fetchAccounts()
        }
    }
    
    func account(with accountID: AccountID) throws -> Account? {
        return try queue.sync {
            return try self.fetchAccount(with: accountID)
        }
    }
    
    func update(_ account: Account, with label: String?) throws {
        try queue.sync {
            guard
                let db = self.db
            else { throw FileStoreError.notSetup }
            try db.transaction {
                let update = FileStoreSchema.account
                    .filter(FileStoreSchema.identifier == account.identifier)
                    .update(FileStoreSchema.label <- label)
                _ = try db.run(update)
            }
        }
    }
    
    func addAccount(with url: URL, username: String) throws -> Account {
        return try queue.sync {
            guard
                let db = self.db
            else { throw FileStoreError.notSetup }
            
            var account: Account?
            try db.transaction {
                let identifier = UUID().uuidString.lowercased()
                let standardizedURL = url.standardized
                let insert = FileStoreSchema.account.insert(
                    FileStoreSchema.identifier <- identifier,
                    FileStoreSchema.url <- standardizedURL,
                    FileStoreSchema.username <- username
                )
                _ = try db.run(insert)
                account = Account(identifier: identifier, url: standardizedURL, username: username, label: nil)
            }
            
            guard
                let result = account
            else { throw FileStoreError.internalError }
            
            return result
        }
    }
    
    func remove(_ account: Account) throws {
        try queue.sync {
            guard
                let db = self.db
            else { throw FileStoreError.notSetup }
            
            try db.transaction {
                try db.run(FileStoreSchema.account.filter(FileStoreSchema.identifier == account.identifier).delete())
                
                let resoruceID = ResourceID(accountID: account.identifier, components: [])
                let changeSet = StoreChangeSet()
                try self.clearCollection(with: resoruceID, in: db, with: changeSet)
            }
        }
    }
    
    // MARK: Resources
    
    func resource(with resourceID: ResourceID) throws -> Resource? {
        return try queue.sync {
            guard
                let db = self.db
                else { throw FileStoreError.notSetup }
            var resource: Resource?
            try db.transaction {
                resource = try self.resource(with: resourceID, in: db)
            }
            return resource
        }
    }
    
    func content(ofResourceWith resourceID: ResourceID) throws -> [Resource] {
        return try queue.sync {
            guard
                let db = self.db
                else { throw FileStoreError.notSetup }
            
            var result: [Resource] = []
            
            try db.transaction {
                
                let href = resourceID.path.href
                let depth = resourceID.path.length
                let hrefPattern = depth == 0 ? "/%" : "\(href)/%"
                let accountID = resourceID.accountID
                
                let query = FileStoreSchema.resource.filter(
                    FileStoreSchema.account_identifier == accountID
                        && FileStoreSchema.href.like(hrefPattern)
                        && FileStoreSchema.depth == depth + 1
                )
                
                for row in try db.prepare(query) {
                    let resource = try self.makeResource(with: row)
                    result.append(resource)
                }
            }
            
            return result
        }
    }

    func update(resourceWith resourceID: ResourceID, using properties: Properties?) throws -> StoreChangeSet {
        return try update(resourceWith: resourceID, using: properties, content: nil)
    }
    
    func update(resourceWith resourceID: ResourceID, using properties: Properties?, content: [String: Properties]?) throws -> StoreChangeSet {
        return try queue.sync {
            guard
                let db = self.db
            else { throw FileStoreError.notSetup }
            
            let changeSet = StoreChangeSet()
            
            try db.transaction {
                
                let timestamp = Date()
                
                if let properties = properties {
                    
                    if try self.updateResource(with: resourceID, using: properties, timestamp: timestamp, in: db, with: changeSet) {
                        
                        var parentResourceID = resourceID.parent
                        while parentResourceID != nil {
                            try self.invalidateCollection(with: parentResourceID!, in: db, with: changeSet)
                            parentResourceID = parentResourceID!.parent
                        }
                        
                        if properties.isCollection == true {
                            if let content = content {
                                try self.updateCollection(with: resourceID, using: content, timestamp: timestamp, in: db, with: changeSet)
                            }
                        } else {
                            try self.clearCollection(with: resourceID, in: db, with: changeSet)
                        }
                    }
                } else {
                    try self.removeResource(with: resourceID, in: db, with: changeSet)
                }
            }
            
            return changeSet
        }
    }
    
    func moveFile(at url: URL, withVersion version: String, toResourceWith resourceID: ResourceID) throws {
        return try queue.sync {
            guard
                let db = self.db
            else { throw FileStoreError.notSetup }
            
            try db.transaction {
                try self.moveFile(at: url, withVersion: version, toResourceWith: resourceID, in: db)
            }
        }
    }
    
    // MARK: - Internal Methods
    
    private func fetchAccounts() throws -> [Account] {
        guard
            let db = self.db
        else { throw FileStoreError.notSetup }
        var result: [Account] = []
        try db.transaction {
            let query = FileStoreSchema.account.select([
                FileStoreSchema.identifier,
                FileStoreSchema.url,
                FileStoreSchema.username,
                FileStoreSchema.label
            ])
            for row in try db.prepare(query) {
                let account = try self.makeAcocunt(with: row)
                result.append(account)
            }
        }
        return result
    }
    
    private func fetchAccount(with accountID: AccountID) throws -> Account? {
        guard
            let db = self.db
            else { throw FileStoreError.notSetup }
        var account: Account? = nil
        try db.transaction {
            let query = FileStoreSchema.account
                .filter(FileStoreSchema.identifier == accountID)
            if let row = try db.pluck(query) {
                account = try self.makeAcocunt(with: row)
            }
        }
        return account
    }
    
    private func makeAcocunt(with row: SQLite.Row) throws -> Account {
        let identifier = row.get(FileStoreSchema.identifier)
        let url = row.get(FileStoreSchema.url)
        let username = row.get(FileStoreSchema.username)
        let label = row.get(FileStoreSchema.label)
        return Account(identifier: identifier, url: url, username: username, label: label)
    }
    
    private func resource(with resoruceID: ResourceID, in db: SQLite.Connection) throws -> Resource? {
        let href = resoruceID.path.href
        let accountID = resoruceID.accountID
        
        let query = FileStoreSchema.resource.filter(
            FileStoreSchema.account_identifier == accountID && FileStoreSchema.href == href
        )
        
        if let row = try db.pluck(query) {
            return try self.makeResource(with: row)
        } else if resoruceID.isRoot {
            let properties = Properties(
                isCollection: true,
                version: UUID().uuidString.lowercased(),
                contentType: nil,
                contentLength: nil,
                modified: nil
            )
            return Resource(
                resourceID: resoruceID,
                dirty: true,
                updated: nil,
                properties: properties,
                fileURL: nil,
                fileVersion: nil
            )
        } else {
            return nil
        }
    }
    
    private func makeResource(with row: SQLite.Row) throws -> Resource {
        let accountID = row.get(FileStoreSchema.account_identifier)
        let path = Path(href: row.get(FileStoreSchema.href))
        let isCollection = row.get(FileStoreSchema.is_collection)
        let dirty = row.get(FileStoreSchema.dirty)
        let version = row.get(FileStoreSchema.version)
        let fileVersion = row.get(FileStoreSchema.file_version)
        let updated = row.get(FileStoreSchema.updated)
        let contentType = row.get(FileStoreSchema.content_type)
        let contentLength = row.get(FileStoreSchema.content_length)
        let modified = row.get(FileStoreSchema.modified)
        
        let resourceID = ResourceID(accountID: accountID, path: path)
        
        let fileURL = self.makeLocalFileURL(with: resourceID)
        
        let properties = Properties(
            isCollection: isCollection,
            version: version,
            contentType: contentType,
            contentLength: contentLength,
            modified: modified
        )
        
        let resource = Resource(
            resourceID: resourceID,
            dirty: dirty,
            updated: updated,
            properties: properties,
            fileURL: fileURL,
            fileVersion: fileVersion
        )
        return resource
    }
    
    private func invalidateCollection(with resourceID: ResourceID, in db: SQLite.Connection, with _: StoreChangeSet) throws {
        
        let href = resourceID.path.href
        let depth = resourceID.path.length
        
        let query = FileStoreSchema.resource.filter(FileStoreSchema.account_identifier == resourceID.accountID && FileStoreSchema.href == href)
        
        if try db.run(query.update(FileStoreSchema.dirty <- true)) == 0 {
            let insert = FileStoreSchema.resource.insert(
                FileStoreSchema.account_identifier <- resourceID.accountID,
                FileStoreSchema.href <- href,
                FileStoreSchema.depth <- depth,
                FileStoreSchema.version <- "",
                FileStoreSchema.is_collection <- true,
                FileStoreSchema.dirty <- true
            )
            _ = try db.run(insert)
        }
    }
    
    private func updateResource(with resourceID: ResourceID, using properties: Properties, dirty: Bool = false, timestamp: Date?, in db: SQLite.Connection, with changeSet: StoreChangeSet) throws -> Bool {
        
        let href = resourceID.path.href
        let query = FileStoreSchema.resource
            .filter(
                FileStoreSchema.account_identifier == resourceID.accountID &&
                    FileStoreSchema.href == href
            )
        
        // Resource is up to date, just updating the timestamp
        if try db.run(query.filter(FileStoreSchema.dirty == false && FileStoreSchema.version == properties.version).update(FileStoreSchema.updated <- timestamp)) > 0 {
            changeSet.insertedOrUpdated.append(resourceID)
            return false
        } else if try db.run(query.update(
            FileStoreSchema.version <- properties.version,
            FileStoreSchema.is_collection <- properties.isCollection,
            FileStoreSchema.dirty <- dirty,
            FileStoreSchema.content_type <- properties.contentType,
            FileStoreSchema.content_length <- properties.contentLength,
            FileStoreSchema.modified <- properties.modified
        )) > 0 {
            changeSet.insertedOrUpdated.append(resourceID)
            return true
        } else {
            _ = try db.run(FileStoreSchema.resource.insert(
                FileStoreSchema.account_identifier <- resourceID.accountID,
                FileStoreSchema.href <- href,
                FileStoreSchema.depth <- resourceID.path.length,
                FileStoreSchema.updated <- timestamp,
                FileStoreSchema.version <- properties.version,
                FileStoreSchema.is_collection <- properties.isCollection,
                FileStoreSchema.dirty <- dirty,
                FileStoreSchema.content_type <- properties.contentType,
                FileStoreSchema.content_length <- properties.contentLength,
                FileStoreSchema.modified <- properties.modified
            ))
            
            changeSet.insertedOrUpdated.append(resourceID)
            return true
        }
    }
    
    private func updateCollection(with resourceID: ResourceID, using content: [String: Properties], timestamp: Date?, in db: SQLite.Connection, with changeSet: StoreChangeSet) throws {
        
        let href = resourceID.path.href
        let hrefPattern = resourceID.path.length == 0 ? "/%" : "\(href)/%"
        
        let query = FileStoreSchema.resource
            .filter(FileStoreSchema.account_identifier == resourceID.accountID && FileStoreSchema.href.like(hrefPattern) && FileStoreSchema.depth == resourceID.path.length + 1)
            .order(FileStoreSchema.href.asc)
            .select(FileStoreSchema.href, FileStoreSchema.version)
        
        var insertOrUpdate: [String: Properties] = content
        
        for row in try db.prepare(query) {
            let path = Path(href: row.get(FileStoreSchema.href))
            let version = row.get(FileStoreSchema.version)
            if let name = path.components.last {
                if let newProeprties = insertOrUpdate[name] {
                    if newProeprties.version == version {
                        insertOrUpdate[name] = nil
                    }
                } else {
                    _ = try self.removeResource(with: resourceID.appending(name), in: db, with: changeSet)
                }
            }
        }
        
        for (name, properties) in insertOrUpdate {
            let childResourceID = resourceID.appending(name)
            _ = try self.updateResource(with: childResourceID, using: properties, dirty: properties.isCollection, timestamp: timestamp, in: db, with: changeSet)
            if properties.isCollection == false {
                _ = try self.clearCollection(with: childResourceID, in: db, with: changeSet)
            }
        }
    }
    
    private func clearCollection(with resourceID: ResourceID, in db: SQLite.Connection, with _: StoreChangeSet) throws {
        
        let href = resourceID.path.href
        let hrefPattern = resourceID.path.length == 0 ? "/%" : "\(href)/%"
        
        let query = FileStoreSchema.resource.filter(
            FileStoreSchema.account_identifier == resourceID.accountID
                && FileStoreSchema.href.like(hrefPattern)
                && FileStoreSchema.depth == resourceID.path.length + 1
        )
        
        _ = try db.run(query.delete())
        
        let fileURL = makeLocalFileURL(with: resourceID)
        
        var coordinatorSuccess = false
        var coordinatorError: NSError?
        fileCoordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordinatorError) { fileURL in
            do {
                try self.fileManager.removeItem(at: fileURL)
                coordinatorSuccess = true
            } catch {
                coordinatorError = error as NSError
            }
        }
        
        if let error = coordinatorError {
            throw error
        } else if coordinatorSuccess == false {
            throw FileStoreError.internalError
        }
    }
    
    private func removeResource(with resourceID: ResourceID, in db: SQLite.Connection, with changeSet: StoreChangeSet) throws {
        
        let query = FileStoreSchema.resource.filter(
            FileStoreSchema.account_identifier == resourceID.accountID && FileStoreSchema.href == resourceID.path.href
        )
        
        if try db.run(query.delete()) > 0 {
            
            let fileURL = makeLocalFileURL(with: resourceID)
            
            var coordinatorSuccess = false
            var coordinatorError: NSError?
            fileCoordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordinatorError) { fileURL in
                do {
                    try self.fileManager.removeItem(at: fileURL)
                    coordinatorSuccess = true
                } catch {
                    coordinatorError = error as NSError
                }
            }
            
            if let error = coordinatorError {
                throw error
            } else if coordinatorSuccess == false {
                throw FileStoreError.internalError
            }
            
            let hrefPattern = resourceID.path.length == 0 ? "/%" : "\(resourceID.path.href)/%"
            
            let query = FileStoreSchema.resource.filter(
                FileStoreSchema.account_identifier == resourceID.accountID
                    && FileStoreSchema.href.like(hrefPattern)
                    && FileStoreSchema.depth == resourceID.path.length + 1
            )
            
            _ = try db.run(query.delete())

            changeSet.deleted.append(resourceID)
        }
    }
    
    private func moveFile(at url: URL, withVersion version: String, toResourceWith resourceID: ResourceID, in db: SQLite.Connection) throws {
        
        let accountID = resourceID.accountID
        let href = resourceID.path.href
        let fileURL = makeLocalFileURL(with: resourceID)
        
        let query = FileStoreSchema.resource.filter(
            FileStoreSchema.account_identifier == accountID && FileStoreSchema.href == href
        )
        
        if let row = try db.pluck(query) {
            if row.get(FileStoreSchema.version) != version {
                throw FileStoreError.versionMismatch
            } else {
                
                try db.run(query.update(FileStoreSchema.file_version <- version))
                
                var coordinatorSuccess = false
                var coordinatorError: NSError?
                self.fileCoordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { fileURL in
                    do {
                        let directory = fileURL.deletingLastPathComponent()
                        try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                        try self.fileManager.moveItem(at: url, to: fileURL)
                        coordinatorSuccess = true
                    } catch {
                        coordinatorError = error as NSError
                    }
                }
                
                if let error = coordinatorError {
                    throw error
                } else if coordinatorSuccess == false {
                    throw FileStoreError.internalError
                }
            }
        } else {
            throw FileStoreError.resourceDoesNotExist
        }
    }
    
    // MARK: HRef & Local File URL
    
    private func makeLocalFileURL(with resource: Resource) -> URL {
        return makeLocalFileURL(with: resource.resourceID)
    }
    
    private func makeLocalFileURL(with resourceID: ResourceID) -> URL {
        let storeBase = directory.appendingPathComponent("files", isDirectory: true)
        let accountBase = storeBase.appendingPathComponent(resourceID.accountID, isDirectory: true)
        let fileURL = accountBase.appending(resourceID.path)
        return fileURL
    }
    
    // MARK: - FileManagerDelegate
    
    func fileManager(_: FileManager, shouldProceedAfterError error: Error, removingItemAt _: URL) -> Bool {
        switch error {
        case let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError:
            return true
        default:
            return false
        }
    }
}

//
//  FileStore.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 02.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import SQLite

public enum FileStoreError: Error {
    case notSetup
    case versionMismatch
    case resourceDoesNotExist
    case internalError
}

public struct FileStoreAccount: StoreAccount {
    
    public let identifier: String
    public let url: URL
    public let username: String
    public let label: String?
    
    public static func ==(lhs: FileStoreAccount, rhs: FileStoreAccount) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    
    public var hashValue: Int {
        return identifier.hashValue
    }
}

public struct FileStoreResource: StoreResource {
    
    public typealias Account = FileStoreAccount
    
    public let account: Account
    public let path: [String]
    public let dirty: Bool
    public let updated: Date?
    
    public let isCollection: Bool
    public let version: String
    
    public let contentType: String?
    public let contentLength: Int?
    public let modified: Date?
    
    public let fileURL: URL?
    public let fileVersion: String?
    
    public var fileState: StoreFileState {
        switch (version, fileVersion) {
        case (_, nil): return .none
        case (let version, let fileVersion) where version == fileVersion: return .valid
        default: return .outdated
        }
    }
    
    public static func ==(lhs: FileStoreResource, rhs: FileStoreResource) -> Bool {
        return lhs.account == rhs.account && lhs.path == rhs.path
    }
    
    public var hashValue: Int {
        return account.hashValue ^ path.count
    }
}

struct FileStoreResourceProperties: StoreResourceProperties {
    let isCollection: Bool
    let version: String
    let contentType: String?
    let contentLength: Int?
    let modified: Date?
}

class FileStoreChangeSet: StoreChangeSet {
    typealias Resource = FileStoreResource
    var insertedOrUpdated: [Resource] = []
    var deleted: [Resource] = []
}

public class FileStore: NSObject, Store, FileManagerDelegate {
    
    public typealias Account = FileStoreAccount
    public typealias Resource = FileStoreResource
    typealias ChangeSet = FileStoreChangeSet
    
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
    
    var accounts: [Account] {
        return queue.sync {
            do {
                return try self.fetchAccounts()
            } catch {
                NSLog("Failed to fetch accounts: \(error)")
                return []
            }
        }
    }
    
    func update(_ account: FileStoreAccount, with label: String?) throws -> FileStoreAccount {
        return try queue.sync {
            guard
                let db = self.db
                else { throw FileStoreError.notSetup }
            var account: Account = account
            try db.transaction {
                let update = FileStoreSchema.account
                    .filter(FileStoreSchema.identifier == account.identifier)
                    .update(FileStoreSchema.label <- label)
                _ = try db.run(update)
                account = Account(identifier: account.identifier,
                                  url: account.url,
                                  username: account.username,
                                  label: label)
            }
            return account
        }
    }
    
    func addAccount(with url: URL, username: String) throws -> Account {
        return try queue.sync {
            guard
                let db = self.db
                else { throw FileStoreError.notSetup }
            
            var account: Account? = nil
            try db.transaction {
                let identifier = UUID().uuidString.lowercased()
                let standardizedURL = url.standardized
                let insert = FileStoreSchema.account.insert(
                    FileStoreSchema.identifier <- identifier,
                    FileStoreSchema.url <- standardizedURL,
                    FileStoreSchema.username <- username)
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
                try db.run(FileStoreSchema.resource.filter(FileStoreSchema.account_identifier == account.identifier).delete())
            }
        }
    }
    
    // MARK: Resources
    
    func resource(of account: Account, at path: [String]) throws -> Resource? {
        return try queue.sync {
            guard
                let db = self.db
                else { throw FileStoreError.notSetup }
            var resource: Resource? = nil
            try db.transaction {
                resource = try self.resource(of: account, at: path, in: db)
            }
            return resource
        }
    }
    
    func contents(of account: FileStoreAccount, at path: [String]) throws -> [FileStoreResource] {
        return try queue.sync {
            guard
                let db = self.db
                else { throw FileStoreError.notSetup }
            
            var result: [Resource] = []
            
            try db.transaction {
                
                let href = self.makeHRef(with: path)
                let hrefPattern = path.count == 0 ? "/%" : "\(href)/%"
                
                let query = FileStoreSchema.resource.filter(
                    FileStoreSchema.account_identifier == account.identifier
                        && FileStoreSchema.href.like(hrefPattern)
                        && FileStoreSchema.depth == path.count + 1)
                
                for row in try db.prepare(query) {
                    let resource = try self.makeResource(with: row, account: account)
                    result.append(resource)
                }
            }
            
            return result
        }
    }

    func update(resourceAt path: [String], of account: Account, with properties: StoreResourceProperties?) throws -> FileStoreChangeSet {
        return try update(resourceAt: path, of: account, with: properties, content: nil)
    }
    
    func update(resourceAt path: [String], of account: Account, with properties: StoreResourceProperties?, content: [String:StoreResourceProperties]?) throws -> FileStoreChangeSet {
        return try queue.sync {
            guard
                let db = self.db
                else { throw FileStoreError.notSetup }

            let changeSet = FileStoreChangeSet()
            
            try db.transaction {
                
                let timestamp = Date()
                
                if let properties = properties {
                    
                    if try self.updateResource(at: path, of: account, with: properties, timestamp: timestamp, in: db, with: changeSet) {
                        
                        var parentPath = path
                        while parentPath.count > 0 {
                            parentPath.removeLast()
                            try self.invalidateCollection(at: parentPath, of: account, in: db, with: changeSet)
                        }
                        
                        if properties.isCollection == true {
                            if let content = content {
                                try self.updateCollection(at: path, of: account, with: content, timestamp: timestamp, in: db, with: changeSet)
                            }
                        } else {
                            try self.clearCollection(at: path, of: account, in: db, with: changeSet)
                        }
                    }
                } else {
                    try self.removeResource(at: path, of: account, in: db, with: changeSet)
                }
            }
            
            return changeSet
        }
    }
    
    func moveFile(at url: URL, withVersion version: String, to resource: Resource) throws -> Resource {
        return try queue.sync {
            guard
                let db = self.db
                else { throw FileStoreError.notSetup }
            
            var resource: FileStoreResource = resource
            try db.transaction {
                resource = try self.moveFile(at: url, withVersion: version, to: resource, in: db)
            }
            return resource
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
    
    private func makeAcocunt(with row: SQLite.Row) throws -> Account {
        let identifier = row.get(FileStoreSchema.identifier)
        let url = row.get(FileStoreSchema.url)
        let username = row.get(FileStoreSchema.username)
        let label = row.get(FileStoreSchema.label)
        return Account(identifier: identifier, url: url, username: username, label: label)
    }
    
    private func resource(of account: Account, at path: [String], in db: SQLite.Connection) throws -> Resource? {
        let href = self.makeHRef(with: path)
        
        let query = FileStoreSchema.resource.filter(
            FileStoreSchema.account_identifier == account.identifier &&
                FileStoreSchema.href == href)
        
        if let row = try db.pluck(query) {
            return try self.makeResource(with: row, account: account)
        } else if path == [] {
            return Resource(account: account,
                            path: path,
                            dirty: true,
                            updated: nil,
                            isCollection: true,
                            version: UUID().uuidString.lowercased(),
                            contentType: nil,
                            contentLength: nil,
                            modified: nil,
                            fileURL: nil,
                            fileVersion: nil)
        } else {
            return nil
        }
    }
    
    private func makeResource(with row: SQLite.Row, account: Account) throws -> Resource {
        let path = makePath(with: row.get(FileStoreSchema.href))
        let isCollection = row.get(FileStoreSchema.is_collection)
        let dirty = row.get(FileStoreSchema.dirty)
        let version = row.get(FileStoreSchema.version)
        let fileVersion = row.get(FileStoreSchema.file_version)
        let updated = row.get(FileStoreSchema.updated)
        let contentType = row.get(FileStoreSchema.content_type)
        let contentLength = row.get(FileStoreSchema.content_length)
        let modified = row.get(FileStoreSchema.modified)
        
        let fileURL = self.makeLocalFileURL(with: path, account: account)
        
        let resource = Resource(account: account,
                                path: path,
                                dirty: dirty,
                                updated: updated,
                                isCollection: isCollection,
                                version: version,
                                contentType: contentType,
                                contentLength: contentLength,
                                modified: modified,
                                fileURL: fileURL,
                                fileVersion: fileVersion)
        return resource
    }
    
    private func invalidateCollection(at path: [String], of account: Account, in db: SQLite.Connection, with changeSet: FileStoreChangeSet) throws {
        
        let href = self.makeHRef(with: path)
        let depth = path.count
        
        let query = FileStoreSchema.resource.filter(FileStoreSchema.account_identifier == account.identifier && FileStoreSchema.href == href)
        
        if try db.run(query.update(FileStoreSchema.dirty <- true)) == 0 {
            let insert = FileStoreSchema.resource.insert(
                FileStoreSchema.account_identifier <- account.identifier,
                FileStoreSchema.href <- href,
                FileStoreSchema.depth <- depth,
                FileStoreSchema.version <- "",
                FileStoreSchema.is_collection <- true,
                FileStoreSchema.dirty <- true)
            _ = try db.run(insert)
        }
    }
    
    private func updateResource(at path: [String], of account: Account, with properties: StoreResourceProperties, dirty: Bool = false, timestamp: Date?, in db: SQLite.Connection, with changeSet: FileStoreChangeSet) throws -> Bool {
        
        let href = makeHRef(with: path)
        let query = FileStoreSchema.resource
            .filter(
                FileStoreSchema.account_identifier == account.identifier &&
                    FileStoreSchema.href == href
        )
        
        // Resource is up to date, just updating the timestamp
        if try db.run(query.filter(FileStoreSchema.dirty == false && FileStoreSchema.version == properties.version).update(FileStoreSchema.updated <- timestamp)) > 0 {
            if let resource = try self.resource(of: account, at: path, in: db) {
                changeSet.insertedOrUpdated.append(resource)
            }
            return false
        }
            
            // Updating the properties of the ressource
        else if try db.run(query.update(FileStoreSchema.version <- properties.version,
                                        FileStoreSchema.is_collection <- properties.isCollection,
                                        FileStoreSchema.dirty <- dirty,
                                        FileStoreSchema.content_type <- properties.contentType,
                                        FileStoreSchema.content_length <- properties.contentLength,
                                        FileStoreSchema.modified <- properties.modified)) > 0 {
            if let resource = try self.resource(of: account, at: path, in: db) {
                changeSet.insertedOrUpdated.append(resource)
            }
            return true
        }
            
            // Insert new resource
        else {
            _ = try db.run(FileStoreSchema.resource.insert(
                FileStoreSchema.account_identifier <- account.identifier,
                FileStoreSchema.href <- href,
                FileStoreSchema.depth <- path.count,
                FileStoreSchema.updated <- timestamp,
                FileStoreSchema.version <- properties.version,
                FileStoreSchema.is_collection <- properties.isCollection,
                FileStoreSchema.dirty <- dirty,
                FileStoreSchema.content_type <- properties.contentType,
                FileStoreSchema.content_length <- properties.contentLength,
                FileStoreSchema.modified <- properties.modified))
            let fileURL = self.makeLocalFileURL(with: path, account: account)
            let resource = Resource(account: account,
                                    path: path,
                                    dirty: dirty,
                                    updated: timestamp,
                                    isCollection: properties.isCollection,
                                    version: properties.version,
                                    contentType: properties.contentType,
                                    contentLength: properties.contentLength,
                                    modified: properties.modified,
                                    fileURL: fileURL,
                                    fileVersion: nil)
            changeSet.insertedOrUpdated.append(resource)
            return true
        }
    }
    
    private func updateCollection(at path: [String], of account: Account, with content: [String:StoreResourceProperties], timestamp: Date?, in db: SQLite.Connection, with changeSet: FileStoreChangeSet) throws {
        
        let href = self.makeHRef(with: path)
        let hrefPattern = path.count == 0 ? "/%" : "\(href)/%"
        
        let query = FileStoreSchema.resource
            .filter( FileStoreSchema.account_identifier == account.identifier && FileStoreSchema.href.like(hrefPattern) && FileStoreSchema.depth == path.count + 1)
            .order(FileStoreSchema.href.asc)
            .select(FileStoreSchema.href, FileStoreSchema.version)
        
        var insertOrUpdate: [String:StoreResourceProperties] = content
        
        for row in try db.prepare(query) {
            let path = self.makePath(with: row.get(FileStoreSchema.href))
            let version = row.get(FileStoreSchema.version)
            if let name = path.last {
                if let newProeprties = insertOrUpdate[name] {
                    if newProeprties.version == version {
                        insertOrUpdate[name] = nil
                    }
                } else {
                    _ = try self.removeResource(at: path, of: account, in: db, with: changeSet)
                }
            }
        }
        
        for (name, properties) in insertOrUpdate {
            var childPath = path
            childPath.append(name)
            _ = try self.updateResource(at: childPath, of: account, with: properties, dirty: properties.isCollection, timestamp: timestamp, in: db, with: changeSet)
            if properties.isCollection == false {
                _ = try self.clearCollection(at: childPath, of: account, in: db, with: changeSet)
            }
        }
    }
    
    private func clearCollection(at path: [String], of account: Account, in db: SQLite.Connection, with changeSet: FileStoreChangeSet) throws {
        let href = self.makeHRef(with: path)
        let hrefPattern = path.count == 0 ? "/%" : "\(href)/%"
        
        let query = FileStoreSchema.resource.filter(
            FileStoreSchema.account_identifier == account.identifier
                && FileStoreSchema.href.like(hrefPattern)
                && FileStoreSchema.depth == path.count + 1)
        
        _ = try db.run(query.delete())
        
        let fileURL = makeLocalFileURL(with: path, account: account)
        
        var coordinatorSuccess = false
        var coordinatorError: NSError? = nil
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
    
    private func removeResource(at path: [String], of account: Account, in db: SQLite.Connection, with changeSet: FileStoreChangeSet) throws {
        
        let href = self.makeHRef(with: path)
        let query = FileStoreSchema.resource.filter(FileStoreSchema.account_identifier == account.identifier && FileStoreSchema.href == href)
        
        if try db.run(query.delete()) > 0 {
            
            let fileURL = makeLocalFileURL(with: path, account: account)
            
            var coordinatorSuccess = false
            var coordinatorError: NSError? = nil
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
            
            let hrefPattern = path.count == 0 ? "/%" : "\(href)/%"
            
            let query = FileStoreSchema.resource.filter(
                FileStoreSchema.account_identifier == account.identifier
                    && FileStoreSchema.href.like(hrefPattern)
                    && FileStoreSchema.depth == path.count + 1)
            
            let mightBeACollection = try db.run(query.delete()) > 0
            
            let resource = Resource(account: account,
                                    path: path,
                                    dirty: false,
                                    updated: nil,
                                    isCollection: mightBeACollection,
                                    version: UUID().uuidString,
                                    contentType: nil,
                                    contentLength: nil,
                                    modified: nil,
                                    fileURL: nil,
                                    fileVersion: nil)
            changeSet.deleted.append(resource)
        }
    }
    
    private func moveFile(at url: URL, withVersion version: String, to resource: Resource, in db: SQLite.Connection) throws -> Resource {
        let href = makeHRef(with: resource.path)
        let fileURL = makeLocalFileURL(with: resource)
        
        let query = FileStoreSchema.resource.filter(
            FileStoreSchema.account_identifier == resource.account.identifier &&
                FileStoreSchema.href == href
        )
        
        if let row = try db.pluck(query) {
            if row.get(FileStoreSchema.version) != version {
                throw FileStoreError.versionMismatch
            } else {
                
                try db.run(query.update(FileStoreSchema.file_version <- version))
                
                var coordinatorSuccess = false
                var coordinatorError: NSError? = nil
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
                
                return Resource(account: resource.account,
                                path: resource.path,
                                dirty: resource.dirty,
                                updated: resource.updated,
                                isCollection: resource.isCollection,
                                version: resource.version,
                                contentType: resource.contentType,
                                contentLength: resource.contentLength,
                                modified: resource.modified,
                                fileURL: fileURL,
                                fileVersion: version)
            }
        } else {
            throw FileStoreError.resourceDoesNotExist
        }
    }
    
    // MARK: HRef & Local File URL
    
    private func makeHRef(with path: [String]) -> String {
        return "/\(path.joined(separator: "/"))"
    }
    
    private func makePath(with href: String) -> [String] {
        let path: [String] = href.components(separatedBy: "/")
        return Array(path.dropFirst(1))
    }
    
    private func makeLocalFileURL(with path: [String]) -> URL {
        let baseDirectory = directory.appendingPathComponent("files", isDirectory: true)
        return baseDirectory.appendingPathComponent(path.joined(separator: "/"))
    }
    
    private func makeLocalFileURL(with resource: Resource) -> URL {
        return makeLocalFileURL(with: resource.path, account: resource.account)
    }
    
    private func makeLocalFileURL(with path: [String], account: Account) -> URL {
        let storeBase = directory.appendingPathComponent("files", isDirectory: true)
        let accountBase = storeBase.appendingPathComponent(account.identifier, isDirectory: true)
        let fileURL = accountBase.appendingPathComponent(path.joined(separator: "/"))
        return fileURL
    }
    
    // MARK: - FileManagerDelegate
    
    public func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, removingItemAt URL: URL) -> Bool {
        switch error {
        case let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError:
            return true
        default:
            return false
        }
    }
}


//
//  FileStoreSchema.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 15.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import SQLite

class FileStoreSchema {
    
    static let account = Table("account")
    static let resource = Table("resource")
    
    static let identifier = Expression<String>("identifier")
    static let url = Expression<URL>("url")
    static let username = Expression<String>("username")
    static let dirty = Expression<Bool>("dirty")
    static let href = Expression<String>("href")
    static let depth = Expression<Int>("depth")
    static let version = Expression<String>("version")
    static let file_version = Expression<String?>("file_version")
    static let is_collection = Expression<Bool>("is_collection")
    static let account_identifier = Expression<String>("account_identifier")
    static let label = Expression<String?>("label")
    static let updated = Expression<Date?>("updated")
    static let modified = Expression<Date?>("modified")
    static let content_type = Expression<String?>("content_type")
    static let content_length = Expression<Int?>("content_length")
    
    let directory: URL
    required init(directory: URL) {
        self.directory = directory
    }
    
    func create() throws -> SQLite.Connection {
        let db = try createDatabase()
        
        switch readCurrentVersion() {
        case 0:
            try createDirectories()
            try setup(db)
            try writeCurrentVersion(1)
        default:
            break
        }
        
        return db
    }
    
    // MARK: Database
    
    private func createDatabase() throws -> SQLite.Connection {
        let db = try Connection(databaseLocation.path)
        
        db.busyTimeout = 5
        db.busyHandler({ tries in
            if tries >= 3 {
                return false
            }
            return true
        })
        
        return db
    }
    
    private func setup(_ db: SQLite.Connection) throws {
        try db.run(FileStoreSchema.account.create { t in
            t.column(FileStoreSchema.identifier, primaryKey: true)
            t.column(FileStoreSchema.url)
            t.column(FileStoreSchema.username)
            t.column(FileStoreSchema.label)
        })
        try db.run(FileStoreSchema.account.createIndex(FileStoreSchema.url))
        try db.run(FileStoreSchema.resource.create { t in
            t.column(FileStoreSchema.account_identifier)
            t.column(FileStoreSchema.href)
            t.column(FileStoreSchema.depth)
            t.column(FileStoreSchema.is_collection)
            t.column(FileStoreSchema.version)
            t.column(FileStoreSchema.file_version)
            t.column(FileStoreSchema.dirty)
            t.column(FileStoreSchema.updated)
            t.column(FileStoreSchema.modified)
            t.column(FileStoreSchema.content_type)
            t.column(FileStoreSchema.content_length)
            t.unique([FileStoreSchema.account_identifier, FileStoreSchema.href])
            t.foreignKey(FileStoreSchema.account_identifier, references: FileStoreSchema.account, FileStoreSchema.identifier, update: .cascade, delete: .cascade)
        })
        try db.run(FileStoreSchema.resource.createIndex(FileStoreSchema.href))
        try db.run(FileStoreSchema.resource.createIndex(FileStoreSchema.depth))
    }
    
    private func createDirectories() throws {
        try FileManager.default.createDirectory(at: fileLocation, withIntermediateDirectories: true, attributes: nil)
    }
    
    private var databaseLocation: URL {
        return directory.appendingPathComponent("db.sqlite", isDirectory: false)
    }
    
    private var fileLocation: URL {
        return directory.appendingPathComponent("files", isDirectory: true)
    }
    
    // MARK: Version
    
    var version: Int {
        return readCurrentVersion()
    }
    
    private func readCurrentVersion() -> Int {
        let url = directory.appendingPathComponent("version.txt")
        do {
            let versionText = try String(contentsOf: url)
            guard let version = Int(versionText) else { return 0 }
            return version
        } catch {
            return 0
        }
    }
    
    private func writeCurrentVersion(_ version: Int) throws {
        let url = directory.appendingPathComponent("version.txt")
        let versionData = String(version).data(using: .utf8)
        try versionData?.write(to: url)
    }
}

extension URL: Value {
    public static var declaredDatatype: String {
        return String.declaredDatatype
    }
    public static func fromDatatypeValue(_ datatypeValue: String) -> URL {
        return URL(string: datatypeValue)!
    }
    public var datatypeValue: String {
        return self.absoluteString
    }
}

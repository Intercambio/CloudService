//
//  Store.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 02.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

public class StoreChangeSet {
    public var insertedOrUpdated: [Resource] = []
    public var deleted: [Resource] = []
}

public protocol Store {
    var accounts: [Account] { get }
    func addAccount(with url: URL, username: String) throws -> Account
    func update(_ account: Account, with label: String?) throws -> Account
    func remove(_ account: Account) throws -> Void
    
    func resource(with resourceID: ResourceID) throws -> Resource?
    func contents(of account: Account, at path: Path) throws -> [Resource]
    
    func update(resourceOf account: Account, at path: Path, with properties: Properties?) throws -> StoreChangeSet
    func update(resourceOf account: Account, at path: Path, with properties: Properties?, content: [String: Properties]?) throws -> StoreChangeSet
    
    func moveFile(at url: URL, withVersion version: String, to resource: Resource) throws -> Resource
}

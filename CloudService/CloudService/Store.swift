//
//  Store.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 02.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

public class StoreChangeSet {
    public var insertedOrUpdated: [ResourceID] = []
    public var deleted: [ResourceID] = []
}

public protocol Store {
    func allAccounts() throws -> [Account]
    func account(with identifier: AccountID) throws -> Account?
    
    func addAccount(with url: URL, username: String) throws -> Account
    func update(_ account: Account, with label: String?) throws -> Void
    func remove(_ account: Account) throws -> Void
    
    func resource(with resourceID: ResourceID) throws -> Resource?
    func contents(ofResourceWith resourceID: ResourceID) throws -> [Resource]
    
    func update(resourceWith resourceID: ResourceID, using properties: Properties?) throws -> StoreChangeSet
    func update(resourceWith resourceID: ResourceID, using properties: Properties?, content: [String: Properties]?) throws -> StoreChangeSet
    
    func moveFile(at url: URL, withVersion version: String, toResourceWith resourceID: ResourceID) throws -> Void
}

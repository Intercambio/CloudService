//
//  Store.swift
//  CloudStore
//
//  Created by Tobias Kräntzer on 02.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

public protocol StoreAccount: Equatable, Hashable {
    var identifier: String { get }
    var username: String { get }
    var url: URL { get }
    var label: String? { get }
}

public protocol StoreResourceProperties {
    var isCollection: Bool { get }
    var version: String { get }
}

public protocol StoreResource: StoreResourceProperties, Equatable, Hashable {
    associatedtype Account: StoreAccount
    var account: Account { get }
    var path: [String] { get }
    var dirty: Bool { get }
}

public protocol StoreChangeSet {
    associatedtype Resource: StoreResource
    var insertedOrUpdated: [Resource] { get }
    var deleted: [Resource] { get }
}

protocol Store {
    associatedtype Account: StoreAccount
    associatedtype Resource: StoreResource
    associatedtype ChangeSet: StoreChangeSet
    
    var accounts: [Account] { get }
    func addAccount(with url: URL, username: String) throws -> Account
    func update(_ account: Account, with label: String?) throws -> Account
    func remove(_ account: Account) throws -> Void
    
    func resource(of account: Account, at path: [String]) throws -> Resource?
    func contents(of account: Account, at path: [String]) throws -> [Resource]
    
    func update(resourceAt path: [String], of account: Account, with properties: StoreResourceProperties?) throws -> ChangeSet
    func update(resourceAt path: [String], of account: Account, with properties: StoreResourceProperties?, content: [String:StoreResourceProperties]?) throws -> ChangeSet
}

extension StoreResource {
    public var remoteURL: URL {
        return account.url.appendingPathComponent(path.joined(separator: "/"))
    }
}

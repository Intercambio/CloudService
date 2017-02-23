//
//  ResourceID.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 23.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

public typealias AccountID = String

public struct ResourceID: Hashable, Equatable, CustomStringConvertible {
    public let accountID: AccountID
    public let path: Path
    public init(accountID: Account.Identifier, path: Path) {
        self.accountID = accountID
        self.path = path
    }
    public init(accountID: Account.Identifier, components: [String]) {
        self.accountID = accountID
        self.path = Path(components: components)
    }
    public init?(uri: URL) {
        guard
            uri.scheme == "resource",
            let host = uri.host
            else { return nil }
        
        self.accountID = host
        self.path = Path(href: uri.path)
    }
    public var uri: URL? {
        var components = URLComponents()
        components.scheme = "resource"
        components.host = accountID
        components.path = path.href
        return components.url
    }
    public var name: String {
        return path.name
    }
    public var parent: ResourceID? {
        guard
            let parentPath = path.parent
            else { return nil }
        return ResourceID(accountID: accountID, path: parentPath)
    }
    public func appending(_ component: String) -> ResourceID {
        return ResourceID(accountID: accountID, path: path.appending(component))
    }
    public func appending(_ components: [String]) -> ResourceID {
        return ResourceID(accountID: accountID, path: path.appending(components))
    }
    public var isRoot: Bool {
        return path.isRoot
    }
    public func isParent(of resourceID: ResourceID) -> Bool {
        guard
            accountID == resourceID.accountID
            else { return false }
        return self.path.isParent(of: resourceID.path)
    }
    public func isChild(of resourceID: ResourceID) -> Bool {
        guard
            accountID == resourceID.accountID
            else { return false }
        return self.path.isChild(of: resourceID.path)
    }
    public func isAncestor(of resourceID: ResourceID) -> Bool {
        guard
            accountID == resourceID.accountID
            else { return false }
        return self.path.isAncestor(of: resourceID.path)
    }
    public func isDescendant(of resourceID: ResourceID) -> Bool {
        guard
            accountID == resourceID.accountID
            else { return false }
        return self.path.isDescendant(of: resourceID.path)
    }
    public static func ==(lhs: ResourceID, rhs: ResourceID) -> Bool {
        return lhs.accountID == rhs.accountID && lhs.path == rhs.path
    }
    public var hashValue: Int {
        return accountID.hashValue ^ path.hashValue
    }
    public var description: String {
        guard
            let uri = self.uri
            else {
                return "(resource: \(accountID) - \(path); invalid)"
        }
        return "\(uri.absoluteString)"
    }
}

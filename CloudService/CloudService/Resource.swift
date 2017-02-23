//
//  Resource.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 21.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

public struct Resource: Hashable, Equatable {
    
    public enum FileState {
        case none
        case outdated
        case valid
    }
    
    public let account: Account
    public let path: Path
    public let dirty: Bool
    public let updated: Date?
    
    public let properties: Properties
    
    public let fileURL: URL?
    let fileVersion: String?
    
    public var fileState: FileState {
        switch (properties.version, fileVersion) {
        case (_, nil): return .none
        case (let version, let fileVersion) where version == fileVersion: return .valid
        default: return .outdated
        }
    }
    
    public var resouceID: ResourceID {
        return ResourceID(accountID: account.identifier, path: path)
    }
    
    public static func ==(lhs: Resource, rhs: Resource) -> Bool {
        return lhs.resouceID == rhs.resouceID
    }
    
    public var hashValue: Int {
        return resouceID.hashValue
    }
}

extension Resource {
    public var remoteURL: URL {
        return account.url.appending(path).standardized
    }
}

//
//  Account.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 21.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

public struct Account: Hashable, Equatable {
    
    public typealias Identifier = String
    
    public let identifier: Identifier
    public let url: URL
    public let username: String
    public let label: String?
    public static func ==(lhs: Account, rhs: Account) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    public var hashValue: Int {
        return identifier.hashValue
    }
}

//
//  Properties.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 21.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

public struct Properties {
    public let isCollection: Bool
    public var version: String
    public var contentType: String?
    public var contentLength: Int?
    public var modified: Date?
}

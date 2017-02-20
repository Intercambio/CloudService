//
//  Path.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 20.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

public struct Path: Hashable, Equatable, CustomStringConvertible {
    
    public let components: [String]
    
    public init(components: [String]) {
        self.components = components
    }
    
    public init(href: String) {
        let path: [String] = href.components(separatedBy: "/")
        self.components = Array(path.dropFirst(1))
    }
    
    private func makePath(with href: String) -> [String] {
        let path: [String] = href.components(separatedBy: "/")
        return Array(path.dropFirst(1))
    }
    
    public var href: String {
        return "/\(components.joined(separator: "/"))"
    }
    
    public var parent: Path? {
        guard
            components.count > 0
            else { return nil }
        
        return Path(components: Array(components.dropLast(1)))
    }
    
    public var hashValue: Int {
        return components.count
    }
    
    public static func ==(lhs: Path, rhs: Path) -> Bool {
        guard
            lhs.components.count == rhs.components.count
            else { return false }
        
        return zip(lhs.components, rhs.components).contains { (lhs, rhs) -> Bool in
            return lhs != rhs
        } == false
    }
    
    public var description: String {
        return href
    }
}

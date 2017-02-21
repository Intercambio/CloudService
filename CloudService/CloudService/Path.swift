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

    public init() {
        self.components = []
    }
    
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
    
    public var length: Int {
        return components.count
    }
    
    public var href: String {
        return "/\(components.joined(separator: "/"))"
    }
    
    public var isRoot: Bool {
        return components.count == 0
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
    
    public func isParent(_ path: Path) -> Bool {
        return parent == path
    }
    
    public func isChild(_ path: Path) -> Bool {
        return path.parent == self
    }
    
    public func isAncestor(_ path: Path) -> Bool {
        return self != path && components.starts(with: path.components)
    }
    
    public func isDescendant(_ path: Path) -> Bool {
        return self != path && path.components.starts(with: components)
    }
    
    public func appending(_ name: String) -> Path {
        var components = self.components
        components.append(name)
        return Path(components: components)
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

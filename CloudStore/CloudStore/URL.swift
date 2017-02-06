//
//  URL.swift
//  CloudStore
//
//  Created by Tobias Kräntzer on 02.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

extension URL {
    func pathComponents(relativeTo baseURL: URL) -> [String]? {
        guard
            baseURL.scheme == scheme,
            baseURL.host == host,
            baseURL.user == user,
            baseURL.port == port
            else { return nil }
        
        var path = pathComponents
        if path.starts(with: baseURL.pathComponents) {
            path.removeFirst(baseURL.pathComponents.count)
            return path
        } else {
            return nil
        }
    }
}

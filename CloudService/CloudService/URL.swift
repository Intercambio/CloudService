//
//  URL.swift
//  CloudService
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
        
        let basePath = baseURL.pathComponents.count == 0 ? ["/"] : baseURL.pathComponents
        var path = pathComponents
        if path.starts(with: basePath) {
            path.removeFirst(basePath.count)
            return path
        } else {
            return nil
        }
    }
}

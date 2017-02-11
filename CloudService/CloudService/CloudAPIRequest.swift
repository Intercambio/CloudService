//
//  CloudAPIRequest.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 06.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation

extension URLRequest {
    
    static func makePropFindRequest(for url: URL, with depth: CloudAPIRequestDepth = .collection) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue(depth.rawValue, forHTTPHeaderField: "Depth")
        return request
    }
    
}

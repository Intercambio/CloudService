//
//  ResourceAPIResponse.swift
//  CloudService
//
//  Created by Tobias Kraentzer on 06.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import Foundation
import PureXML

public struct ResourceAPIResponse {
    public let resources: [ResourceAPIResource]
    
    init(document: PXDocument, baseURL: URL) throws {
        guard
            document.root.qualifiedName == PXQName(name: "multistatus", namespace: "DAV:")
        else { throw CloudServiceError.invalidResponse }
        
        var resources: [ResourceAPIResource] = []
        
        for node in document.root.nodes(forXPath: "./d:response", usingNamespaces: ["d": "DAV:"]) {
            guard
                let element = node as? PXElement
            else { continue }
            
            let resource = try ResourceAPIResource(element: element, baseURL: baseURL)
            resources.append(resource)
        }
        
        self.resources = resources
    }
}

public struct ResourceAPIResource {
    
    public let url: URL
    
    public func element(for property: PXQName) -> PXElement? {
        return properties[property]?.root
    }
    
    private let properties: [PXQName: PXDocument]
    
    init(element: PXElement, baseURL: URL) throws {
        let namespace = ["d": "DAV:"]
        
        guard
            let urlElement = element.nodes(forXPath: "./d:href", usingNamespaces: namespace).first as? PXElement,
            let urlString = urlElement.stringValue,
            let url = URL(string: urlString, relativeTo: baseURL)
        else { throw CloudServiceError.invalidResponse }
        
        var properties: [PXQName: PXDocument] = [:]
        
        for element in element.nodes(forXPath: "./d:propstat", usingNamespaces: namespace) {
            guard
                let propstats = element as? PXElement,
                let statusElement = propstats.nodes(forXPath: "./d:status", usingNamespaces: namespace).first as? PXElement,
                let statusString = statusElement.stringValue,
                ResourceAPIResource.makeStatus(with: statusString) == 200,
                let prop = propstats.nodes(forXPath: "./d:prop", usingNamespaces: namespace).first as? PXElement
            else { continue }
            
            prop.enumerateElements { element, _ in
                let name = element.qualifiedName
                let document = PXDocument(element: element)
                properties[name] = document
            }
        }
        
        self.url = url
        self.properties = properties
    }
    
    private static func makeStatus(with statusLine: String) -> Int {
        let components = statusLine.components(separatedBy: " ") // HTTP/1.1 200 OK
        if components.count == 3 {
            return Int(components[1]) ?? -1
        } else {
            return -1
        }
    }
}

extension ResourceAPIResource {
    
    public var etag: String? {
        guard
            let element = element(for: PXQN("DAV:", "getetag"))
        else { return nil }
        
        return element.stringValue
    }
    
    public var isCollection: Bool {
        guard
            let element = element(for: PXQN("DAV:", "resourcetype"))
        else { return false }
        
        return element.nodes(forXPath: "./d:collection", usingNamespaces: ["d": "DAV:"]).count > 0
    }
    
    public var contentType: String? {
        guard
            let element = element(for: PXQN("DAV:", "getcontenttype"))
        else { return nil }
        
        return element.stringValue
    }
    
    public var contentLength: Int? {
        guard
            let element = element(for: PXQN("DAV:", "getcontentlength")),
            let stringValue = element.stringValue
        else { return nil }
        
        return Int(stringValue)
    }
    
    public var modified: Date? {
        guard
            let element = element(for: PXQN("DAV:", "getlastmodified")),
            let stringValue = element.stringValue
        else { return nil }
        
        return ResourceAPIResource.dateFormatter.date(from: stringValue)
    }
    
    private static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter
    }()
    
}

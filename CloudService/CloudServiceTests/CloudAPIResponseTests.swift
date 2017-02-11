//
//  CloudAPIResponseTests.swift
//  CloudServiceTests
//
//  Created by Tobias Kraentzer on 06.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
import PureXML
@testable import CloudService

class CloudAPIResponseTests: XCTestCase {
    
    func testParseResponse() {
        guard
            let document = PXDocument(named: "propfind.xml", in: Bundle(for: CloudAPIResponseTests.self)),
            let baseURL = URL(string: "https://example.com/")
            else { XCTFail(); return }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        
        do {
            
            let response = try CloudAPIResponse(document: document, baseURL: baseURL)
            
            XCTAssertEqual(response.resources.count, 6)
            
            XCTAssertTrue(response.resources[0].isCollection)
            
            let resource = response.resources[1]
            XCTAssertEqual(resource.url.absoluteString, "https://example.com/webdav/Noten/%20St.%20James%20Infirmary.pdf")
            XCTAssertEqual(resource.etag, "daf566feead4f993a07c2acf71dae583")
            XCTAssertFalse(resource.isCollection)
            XCTAssertEqual(resource.contentLength, 38059)
            XCTAssertEqual(resource.contentType, "application/pdf")
            XCTAssertEqual(resource.modified, formatter.date(from: "Fri, 17 Jul 2015 15:18:09 GMT"))
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
}

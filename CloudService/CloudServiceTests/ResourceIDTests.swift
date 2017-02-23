//
//  ResourceIDTests.swift
//  CloudService
//
//  Created by Tobias Kräntzer on 23.02.17.
//  Copyright © 2017 Tobias Kräntzer. All rights reserved.
//

import XCTest
import CloudService

class ResourceIDTests: XCTestCase {
    
    func testResourceURI() {
        let idA = ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))
        XCTAssertEqual(idA.uri!.absoluteString, "resource://abc/a/b/c")
        XCTAssertEqual(ResourceID(uri: idA.uri!), idA)
        
        let idB = ResourceID(accountID: "abc", path: Path(components: []))
        XCTAssertEqual(idB.uri!.absoluteString, "resource://abc/")
        XCTAssertEqual(ResourceID(uri: idB.uri!), idB)
    }
    
    func testResourceIDEquatable() {
        
        let idA = ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))
        let idB = ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))
        let idC = ResourceID(accountID: "abc", path: Path(components: ["a", "b", "x"]))
        let idD = ResourceID(accountID: "xyz", path: Path(components: ["a", "b", "c"]))
        
        XCTAssertEqual(idA, idB)
        XCTAssertEqual(idB, idA)
        XCTAssertNotEqual(idA, idC)
        XCTAssertNotEqual(idA, idD)
    }
    
    func testResourceIDIsParent() {
        
        let id = ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))
        
        XCTAssertTrue(id.isParent(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c", "d"]))))
        
        XCTAssertFalse(id.isParent(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c", "d", "e"]))))
        XCTAssertFalse(id.isParent(of: ResourceID(accountID: "xyz", path: Path(components: ["a", "b", "c", "d"]))))
        XCTAssertFalse(id.isParent(of: ResourceID(accountID: "abc", path: Path(components: ["1", "2", "3"]))))
        XCTAssertFalse(id.isParent(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))))
    }
    
    func testResourceIDIsChild() {
        
        let id = ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))
        
        XCTAssertTrue(id.isChild(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b"]))))
        
        XCTAssertFalse(id.isChild(of: ResourceID(accountID: "abc", path: Path(components: ["a"]))))
        XCTAssertFalse(id.isChild(of: ResourceID(accountID: "xyz", path: Path(components: ["a", "b"]))))
        XCTAssertFalse(id.isChild(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))))
        XCTAssertFalse(id.isChild(of: ResourceID(accountID: "abc", path: Path(components: ["x", "b"]))))
    }
    
    func testResourceIDIsAncestor() {
        
        let id = ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))
        
        XCTAssertTrue(id.isAncestor(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c", "d"]))))
        XCTAssertTrue(id.isAncestor(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c", "d", "e"]))))
        
        XCTAssertFalse(id.isAncestor(of: ResourceID(accountID: "xyz", path: Path(components: ["a", "b", "c", "d"]))))
        XCTAssertFalse(id.isAncestor(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))))
        XCTAssertFalse(id.isAncestor(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b"]))))
    }
    
    func testResourceIDIsDescendant() {
        
        let id = ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))

        XCTAssertTrue(id.isDescendant(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b"]))))
        XCTAssertTrue(id.isDescendant(of: ResourceID(accountID: "abc", path: Path(components: []))))
        
        XCTAssertFalse(id.isDescendant(of: ResourceID(accountID: "xyz", path: Path(components: ["a", "b"]))))
        XCTAssertFalse(id.isDescendant(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c"]))))
        XCTAssertFalse(id.isDescendant(of: ResourceID(accountID: "abc", path: Path(components: ["a", "b", "c", "d"]))))
    }
}

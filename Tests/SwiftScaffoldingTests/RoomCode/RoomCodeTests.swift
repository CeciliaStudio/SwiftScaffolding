//
//  RoomCodeTests.swift
//  SwiftScaffolding
//
//  Created by AnemoFlower on 2026/2/28.
//

import XCTest
@testable import SwiftScaffolding

class RoomCodeTests: XCTestCase {
    func testGenerate() {
        print(RoomCode.generate())
    }
    
    func testVerify() {
        XCTAssert(RoomCode.isValid(code: "U/ZZZZ-ZZZZ-ZZZZ-ZZZZ"))
        XCTAssert(RoomCode.isValid(code: "U/UTVM-MNFM-KVLW-FVWS"))
        XCTAssertFalse(RoomCode.isValid(code: "U/ZZZZ-ZZZZ-ZZZZ-ZZZY"))
        XCTAssertFalse(RoomCode.isValid(code: "咕咕嘎嘎"))
        XCTAssertFalse(RoomCode.isValid(code: "U/0123-4567-89AB-CDEF"))
    }
}

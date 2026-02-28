//
//  ByteBufferTests.swift
//  SwiftScaffolding
//
//  Created by AnemoFlower on 2026/2/28.
//

import XCTest
@testable import SwiftScaffolding

class ByteBufferTests: XCTestCase {
    func testRead() throws {
        let buf: ByteBuffer = .init(data: .init([72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100, 33, 42, 0, 1, 2, 3]))
        XCTAssertEqual(try buf.readString(13), "Hello, world!")
        XCTAssertEqual(try buf.readUInt8(), 42)
        XCTAssertEqual(try buf.readData(length: 4), Data([0x00, 0x01, 0x02, 0x03]))
    }
    
    func testThrow() throws {
        let buf: ByteBuffer = .init()
        XCTAssertThrowsError(try buf.readUInt8())
    }
}

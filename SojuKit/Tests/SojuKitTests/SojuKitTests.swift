//
//  SojuKitTests.swift
//  SojuKitTests
//
//  Created on 2026-01-07.
//

import XCTest
@testable import SojuKit

final class SojuKitTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(SojuKit.version, "1.0.0")
    }

    func testWelcomeMessage() {
        let kit = SojuKit()
        let message = kit.getWelcomeMessage()
        XCTAssertTrue(message.contains("Welcome to SojuKit"))
        XCTAssertTrue(message.contains("1.0.0"))
    }
}

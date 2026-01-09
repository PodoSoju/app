//
//  SojuKitTests.swift
//  SojuKitTests
//
//  Created on 2026-01-07.
//

import XCTest
@testable import PodoSojuKit

final class SojuKitTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(SojuKit.version, "1.0.0")
    }
}

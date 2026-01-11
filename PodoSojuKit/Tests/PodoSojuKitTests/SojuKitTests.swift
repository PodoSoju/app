//
//  PodoSojuKitTests.swift
//  PodoSojuKitTests
//
//  Created on 2026-01-07.
//

import XCTest
@testable import PodoPodoSojuKit

final class PodoSojuKitTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(PodoSojuKit.version, "1.0.0")
    }
}

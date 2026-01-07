//
//  Logger+SojuKit.swift
//  SojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import os.log

extension Logger {
    /// Logger for SojuKit framework
    public static let sojuKit = Logger(
        subsystem: "com.soju.app",
        category: "SojuKit"
    )
}

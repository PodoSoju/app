//
//  FileHandle+Extract.swift
//  PodoSojuKit
//
//  Created on 2026-01-09.
//  Based on WhiskyKit's implementation
//

import Foundation

extension FileHandle {
    /// Extract a value of type T from the file at the specified offset
    /// - Parameters:
    ///   - type: The type to extract
    ///   - offset: File offset to read from
    /// - Returns: The extracted value, or nil if reading failed
    func extract<T>(_ type: T.Type, offset: UInt64 = 0) -> T? {
        do {
            try self.seek(toOffset: offset)
            if let data = try self.read(upToCount: MemoryLayout<T>.size) {
                return data.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }
}

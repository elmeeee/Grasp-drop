//
//  OtterLog.swift
//  Otter
//
//  File-based logger for the Otter share layer. The app runs as an accessory
//  process whose stdout is not attached to a terminal, so diagnostics are
//  written to ~/Downloads/Otter/.otter/otter-share.log.
//

import Foundation

enum OtterLog {
    private static let queue = DispatchQueue(label: "otter.share.log")

    static func write(_ message: String) {
        let line = "[\(timestamp())] \(message)\n"
        queue.async {
            guard let url = logURL() else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func logURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = home
            .appendingPathComponent("Downloads/Otter/.otter", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("otter-share.log")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

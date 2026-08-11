//
//  TransferHistory.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation
import SwiftUI

enum VisibilityMode: String, CaseIterable, Identifiable, Codable {
    case everyone = "Visible to Everyone"
    case off = "Receiver Off"

    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .everyone: return "person.3.fill"
        case .off: return "eye.slash.fill"
        }
    }
    
    var statusColor: Color {
        switch self {
        case .everyone: return .green
        case .off: return .gray
        }
    }
}

struct PendingTransfer: Identifiable, Equatable {
    let id: String
    let deviceName: String
    let pinCode: String
    let fileName: String
    let fileSize: Int64
    let fileCount: Int
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

struct ActiveTransfer: Identifiable, Equatable {
    let id: String
    let fileName: String
    var bytesWritten: Int64
    var totalBytes: Int64
    var speedBps: Double
    var status: String
    
    var progressFraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(bytesWritten) / Double(totalBytes)))
    }
    
    var formattedSpeed: String {
        if speedBps >= 1_048_576 {
            return String(format: "%.1f MB/s", speedBps / 1_048_576)
        } else if speedBps >= 1024 {
            return String(format: "%.0f KB/s", speedBps / 1024)
        } else {
            return String(format: "%.0f B/s", speedBps)
        }
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }
}

struct TransferItem: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let filePath: String
    let fileSize: Int64
    let timestamp: Date
    let senderDevice: String
    let isWebUpload: Bool

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var iconName: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg":
            return "photo.fill"
        case "mp4", "mov", "mkv", "avi":
            return "film.fill"
        case "mp3", "m4a", "wav", "flac":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "7z", "rar":
            return "archivebox.fill"
        case "apk":
            return "command.circle.fill"
        default:
            return "doc.fill"
        }
    }
    
    var iconColor: Color {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg":
            return .purple
        case "mp4", "mov", "mkv", "avi":
            return .red
        case "mp3", "m4a", "wav", "flac":
            return .pink
        case "pdf":
            return .orange
        case "zip", "tar", "gz", "7z", "rar":
            return .yellow
        case "apk":
            return .green
        default:
            return .blue
        }
    }
}

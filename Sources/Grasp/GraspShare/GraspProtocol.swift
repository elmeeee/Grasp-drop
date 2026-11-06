//
//  GraspProtocol.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation

enum GraspProtocol {
    static let protocolVersion = "2.2"
    static let defaultPort: UInt16 = 53317
    static let multicastGroup = "224.0.0.167"

    static let schemeHTTPS = "https"
    static let schemeHTTP = "http"

    static let deviceMobile = "mobile"
    static let deviceDesktop = "desktop"
    static let deviceWeb = "web"
}

struct GraspDeviceInfo: Codable, Equatable {
    var alias: String
    var version: String
    var deviceModel: String?
    var deviceType: String?
    var fingerprint: String
    var port: Int?
    var `protocol`: String?
    var download: Bool?
    var announce: Bool?
}

struct GraspFileMetadata: Codable, Equatable {
    var id: String
    var fileName: String
    var size: Int64
    var fileType: String?
    var sha256: String?
    var preview: String?
    var metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, fileName, size, fileType, sha256, preview, metadata
    }
}

struct GraspPrepareUploadRequest: Codable {
    var info: GraspDeviceInfo
    var files: [String: GraspFileMetadata]
}

struct GraspPrepareUploadResponse: Codable {
    var sessionId: String
    var files: [String: String]
}

struct GraspPrepareDownloadResponse: Codable {
    var info: GraspDeviceInfo
    var sessionId: String
    var files: [String: GraspFileMetadata]
}

/// A discovered peer with its resolved IP address.
struct GraspPeer: Identifiable, Equatable {
    var info: GraspDeviceInfo
    var ip: String

    var id: String { info.fingerprint }

    var displayName: String {
        info.alias.isEmpty ? ip : info.alias
    }

    var baseURL: URL? {
        let scheme = info.protocol ?? GraspProtocol.schemeHTTPS
        let port = info.port ?? Int(GraspProtocol.defaultPort)
        return URL(string: "\(scheme)://\(ip):\(port)")
    }
}

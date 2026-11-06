//
//  OtterProtocol.swift
//  Otter
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation

enum OtterProtocol {
    static let protocolVersion = "2.2"
    static let defaultPort: UInt16 = 53317
    static let multicastGroup = "224.0.0.167"

    static let schemeHTTPS = "https"
    static let schemeHTTP = "http"

    static let deviceMobile = "mobile"
    static let deviceDesktop = "desktop"
    static let deviceWeb = "web"
}

struct OtterDeviceInfo: Codable, Equatable {
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

struct OtterFileMetadata: Codable, Equatable {
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

struct OtterPrepareUploadRequest: Codable {
    var info: OtterDeviceInfo
    var files: [String: OtterFileMetadata]
}

struct OtterPrepareUploadResponse: Codable {
    var sessionId: String
    var files: [String: String]
}

struct OtterPrepareDownloadResponse: Codable {
    var info: OtterDeviceInfo
    var sessionId: String
    var files: [String: OtterFileMetadata]
}

/// A discovered peer with its resolved IP address.
struct OtterPeer: Identifiable, Equatable {
    var info: OtterDeviceInfo
    var ip: String

    var id: String { info.fingerprint }

    var displayName: String {
        info.alias.isEmpty ? ip : info.alias
    }

    var baseURL: URL? {
        let scheme = info.protocol ?? OtterProtocol.schemeHTTPS
        let port = info.port ?? Int(OtterProtocol.defaultPort)
        return URL(string: "\(scheme)://\(ip):\(port)")
    }
}

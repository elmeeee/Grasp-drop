//
//  GraspSender.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation
import CryptoKit

@MainActor
final class GraspSender {
    private let info: GraspDeviceInfo
    private let session: URLSession

    init(info: GraspDeviceInfo) {
        self.info = info
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(
            configuration: config, delegate: SelfSignedDelegate(), delegateQueue: nil)
    }

    struct Progress {
        var sent: Int
        var total: Int
    }

    /// Sends files and reports progress as the number of completed files.
    func send(
        files urls: [URL],
        to peer: GraspPeer,
        progress: ((Progress) -> Void)? = nil
    ) async throws {
        guard let base = peer.baseURL else { throw SendError.invalidPeer }
        guard !urls.isEmpty else { return }

        var files: [String: GraspFileMetadata] = [:]
        var order: [String] = []
        var pathByID: [String: URL] = [:]

        for (index, url) in urls.enumerated() {
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()
            let id = "file-\(index)-\(UUID().uuidString.prefix(8))"
            files[id] = GraspFileMetadata(
                id: id,
                fileName: url.lastPathComponent,
                size: Int64(data.count),
                fileType: mimeType(for: url),
                sha256: digest)
            order.append(id)
            pathByID[id] = url
        }

        let request = GraspPrepareUploadRequest(info: info, files: files)
        let prepared: GraspPrepareUploadResponse = try await postJSON(
            request, to: base.appendingPathComponent("/api/localsend/v2/prepare-upload"))

        var sent = 0
        for id in order {
            guard let token = prepared.files[id], let url = pathByID[id] else { continue }
            try await upload(
                file: url, base: base, sessionId: prepared.sessionId,
                fileId: id, token: token)
            sent += 1
            progress?(Progress(sent: sent, total: order.count))
        }
    }

    func sendText(_ text: String, to peer: GraspPeer) async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grasp-text-\(UUID().uuidString).txt")
        try text.data(using: .utf8)?.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        try await send(files: [temp], to: peer)
    }

    private func upload(
        file: URL, base: URL, sessionId: String, fileId: String, token: String
    ) async throws {
        var components = URLComponents(
            url: base.appendingPathComponent("/api/localsend/v2/upload"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "fileId", value: fileId),
            URLQueryItem(name: "token", value: token)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: request, fromFile: file)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SendError.uploadFailed(fileId)
        }
    }

    private func postJSON<Body: Encodable, Result: Decodable>(
        _ body: Body, to url: URL
    ) async throws -> Result {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SendError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(Result.self, from: data)
        case 204:
            return try JSONDecoder().decode(Result.self, from: Data("{}".utf8))
        case 403:
            throw SendError.rejected
        case 401:
            throw SendError.pinRequired
        default:
            throw SendError.status(http.statusCode)
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "mp4": return "video/mp4"
        case "txt": return "text/plain"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }

    enum SendError: LocalizedError {
        case invalidPeer
        case invalidResponse
        case rejected
        case pinRequired
        case uploadFailed(String)
        case status(Int)

        var errorDescription: String? {
            switch self {
            case .invalidPeer: return "Peer address is invalid"
            case .invalidResponse: return "Invalid response from peer"
            case .rejected: return "Transfer rejected by peer"
            case .pinRequired: return "A PIN is required by the peer"
            case .uploadFailed(let id): return "Upload failed for \(id)"
            case .status(let code): return "Peer returned HTTP \(code)"
            }
        }
    }
}

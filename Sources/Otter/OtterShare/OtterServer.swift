//
//  OtterServer.swift
//  Otter
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation
import Network
import CryptoKit

@MainActor
final class OtterServer: ObservableObject {
    @Published private(set) var isRunning = false

    private var listener: NWListener?
    private let identity: OtterIdentity
    private let info: OtterDeviceInfo
    private let filesDirectory: () -> String
    private let onFileReceived: (String, Int64) -> Void

    private var sessions: [String: UploadSession] = [:]
    private var downloadRegistry: [String: String] = [:]

    private struct UploadSession {
        let senderIP: String
        var files: [String: OtterFileMetadata]
        var tokens: [String: String]
    }

    init(
        identity: OtterIdentity,
        info: OtterDeviceInfo,
        filesDirectory: @escaping () -> String,
        onFileReceived: @escaping (String, Int64) -> Void
    ) {
        self.identity = identity
        self.info = info
        self.filesDirectory = filesDirectory
        self.onFileReceived = onFileReceived
    }

    func start(port: UInt16 = OtterProtocol.defaultPort) {
        stop()

        guard let tls = NWProtocolTLS.Options() as NWProtocolTLS.Options?,
              let secIdentity = identity.tlsIdentity else {
            OtterLog.write("Missing TLS identity")
            return
        }
        sec_protocol_options_set_local_identity(
            tls.securityProtocolOptions, secIdentity)
        sec_protocol_options_set_min_tls_protocol_version(
            tls.securityProtocolOptions, .TLSv12)

        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        do {
            let listener = try NWListener(using: params, on: nwPort)
            listener.stateUpdateHandler = { [weak self] state in
                OtterLog.write("listener state: \(state)")
                Task { @MainActor in
                    self?.isRunning = (state == .ready)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } catch {
            OtterLog.write("listener failed: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receiveRequest(connection: connection, buffer: Data())
    }

    private nonisolated func receiveRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var current = buffer
            if let data { current.append(data) }

            if let parsed = HTTPRequest.parse(current) {
                Task { @MainActor in
                    self.route(parsed, on: connection)
                }
                return
            }

            if !isComplete && error == nil {
                self.receiveRequest(connection: connection, buffer: current)
            } else {
                connection.cancel()
            }
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        let path = request.path
        let method = request.method

        switch (method, path) {
        case ("GET", "/api/otter/v2/info"):
            respondJSON(connection, info)

        case ("POST", "/api/otter/v2/register"):
            if let remote = try? JSONDecoder().decode(OtterDeviceInfo.self, from: request.body) {
                print("[OtterShare] Register from \(remote.alias) (\(connection.endpoint))")
            }
            respondJSON(connection, info)

        case ("POST", "/api/otter/v2/prepare-upload"):
            handlePrepareUpload(request, connection)

        case ("POST", "/api/otter/v2/upload"):
            handleUpload(request, connection)

        case ("POST", "/api/otter/v2/cancel"):
            sessions[request.query["sessionId"] ?? ""] = nil
            respondText(connection, status: "200 OK", body: "")

        case ("POST", "/api/otter/v2/prepare-download"):
            handlePrepareDownload(connection)

        case ("GET", "/api/otter/v2/download"):
            handleDownload(request, connection)

        default:
            respondText(connection, status: "404 Not Found", body: "Not Found")
        }
    }

    private func handlePrepareUpload(_ request: HTTPRequest, _ connection: NWConnection) {
        guard let req = try? JSONDecoder().decode(
            OtterPrepareUploadRequest.self, from: request.body) else {
            respondText(connection, status: "400 Bad Request", body: "Invalid body")
            return
        }
        guard !req.files.isEmpty else {
            respondText(connection, status: "204 No Content", body: "")
            return
        }

        let sessionID = UUID().uuidString
        var tokens: [String: String] = [:]
        for fileID in req.files.keys {
            tokens[fileID] = UUID().uuidString
        }
        sessions[sessionID] = UploadSession(
            senderIP: connection.remoteIP,
            files: req.files,
            tokens: tokens)

        let response = OtterPrepareUploadResponse(sessionId: sessionID, files: tokens)
        respondJSON(connection, response)
    }

    private func handleUpload(_ request: HTTPRequest, _ connection: NWConnection) {
        let sessionID = request.query["sessionId"] ?? ""
        let fileID = request.query["fileId"] ?? ""
        let token = request.query["token"] ?? ""

        guard let session = sessions[sessionID],
              session.tokens[fileID] == token,
              let meta = session.files[fileID] else {
            respondText(connection, status: "403 Forbidden", body: "Invalid token")
            return
        }

        let directory = filesDirectory()
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        let target = uniqueURL(directory: directory, name: meta.fileName)

        do {
            try request.body.write(to: target)
        } catch {
            respondText(connection, status: "500 Internal Server Error", body: "Write error")
            return
        }

        if let expected = meta.sha256, !expected.isEmpty {
            let actual = SHA256.hash(data: request.body)
                .map { String(format: "%02x", $0) }.joined()
            if !actual.elementsEqual(expected.lowercased()) {
                OtterLog.write(
                    "checksum mismatch for \(meta.fileName): expected \(expected) size \(meta.size) got \(actual) bytes \(request.body.count)")
                try? FileManager.default.removeItem(at: target)
                respondText(connection, status: "422 Unprocessable Entity", body: "Checksum mismatch")
                return
            }
        }

        print("[OtterShare] Received \(meta.fileName) (\(request.body.count) bytes)")
        onFileReceived(meta.fileName, Int64(request.body.count))
        respondText(connection, status: "200 OK", body: "")
    }

    private func handlePrepareDownload(_ connection: NWConnection) {
        let directory = filesDirectory()
        var files: [String: OtterFileMetadata] = [:]
        var registry: [String: String] = [:]
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) {
            for name in entries where !name.hasPrefix(".") {
                let full = (directory as NSString).appendingPathComponent(name)
                let attrs = try? FileManager.default.attributesOfItem(atPath: full)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let id = UUID().uuidString
                registry[id] = name
                files[id] = OtterFileMetadata(
                    id: id, fileName: name, size: size,
                    fileType: "application/octet-stream")
            }
        }
        downloadRegistry = registry
        let response = OtterPrepareDownloadResponse(
            info: info, sessionId: UUID().uuidString, files: files)
        respondJSON(connection, response)
    }

    private func handleDownload(_ request: HTTPRequest, _ connection: NWConnection) {
        guard let fileID = request.query["fileId"] else {
            respondText(connection, status: "400 Bad Request", body: "Missing fileId")
            return
        }
        let directory = filesDirectory()
        let name = downloadRegistry[fileID] ?? (fileID as NSString).lastPathComponent
        let path = (directory as NSString).appendingPathComponent(name)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            respondText(connection, status: "404 Not Found", body: "Not Found")
            return
        }
        var headers = HTTPResponse(
            status: "200 OK", contentType: "application/octet-stream")
        headers.extraHeaders = [
            "Content-Disposition": "attachment; filename=\"\(name)\""
        ]
        connection.send(content: headers.data(appending: data), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Responses

    private func respondJSON<T: Encodable>(_ connection: NWConnection, _ value: T) {
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        respondText(connection, status: "200 OK", body: String(data: data, encoding: .utf8) ?? "{}",
                    contentType: "application/json")
    }

    private func respondText(
        _ connection: NWConnection, status: String, body: String,
        contentType: String = "text/plain"
    ) {
        let response = HTTPResponse(status: status, contentType: contentType)
        let bodyData = body.data(using: .utf8) ?? Data()
        connection.send(
            content: response.data(appending: bodyData),
            completion: .contentProcessed { _ in connection.cancel() })
    }

    private func uniqueURL(directory: String, name: String) -> URL {
        let base = (directory as NSString).appendingPathComponent(
            (name as NSString).lastPathComponent)
        if !FileManager.default.fileExists(atPath: base) {
            return URL(fileURLWithPath: base)
        }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        for index in 1..<10_000 {
            let candidate = (directory as NSString)
                .appendingPathComponent("\(stem) (\(index)).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return URL(fileURLWithPath: base)
    }
}

private extension NWConnection {
    var remoteIP: String {
        if case let .hostPort(host, _) = endpoint {
            return "\(host)"
        }
        return "unknown"
    }
}

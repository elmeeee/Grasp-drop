//
//  HTTPSupport.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    /// Attempts to parse a complete HTTP request from a buffer. Returns nil when
    /// the buffer does not yet contain the full body (Content-Length not met).
    static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let headerRange = data.range(of: separator) else { return nil }

        let headerData = data.subdata(in: 0..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound

        let body: Data
        if let transferEncoding = headers["transfer-encoding"]?.lowercased(),
           transferEncoding.contains("chunked") {
            guard let decoded = decodeChunked(data.subdata(in: bodyStart..<data.count)) else {
                return nil
            }
            body = decoded
        } else {
            let totalNeeded = bodyStart + contentLength
            guard data.count >= totalNeeded else { return nil }
            body = data.subdata(in: bodyStart..<totalNeeded)
        }

        let rawTarget = parts[1]
        let (path, query) = splitTarget(rawTarget)

        return HTTPRequest(
            method: parts[0], path: path, query: query,
            headers: headers, body: body)
    }

    /// Decodes an HTTP/1.1 chunked body, returning nil if incomplete.
    private static func decodeChunked(_ data: Data) -> Data? {
        var output = Data()
        var index = 0
        let bytes = [UInt8](data)

        while index < bytes.count {
            // Read the chunk size line.
            var lineEnd = index
            while lineEnd + 1 < bytes.count,
                  !(bytes[lineEnd] == 0x0D && bytes[lineEnd + 1] == 0x0A) {
                lineEnd += 1
            }
            guard lineEnd + 1 < bytes.count else { return nil }

            let sizeLine = String(
                bytes: bytes[index..<lineEnd], encoding: .utf8) ?? ""
            let sizeToken = sizeLine.split(separator: ";").first.map(String.init) ?? sizeLine
            guard let chunkSize = Int(sizeToken.trimmingCharacters(in: .whitespaces), radix: 16) else {
                return nil
            }

            let chunkStart = lineEnd + 2
            if chunkSize == 0 { return output } // Last chunk reached.

            let chunkEnd = chunkStart + chunkSize
            guard chunkEnd + 2 <= bytes.count else { return nil }
            output.append(contentsOf: bytes[chunkStart..<chunkEnd])
            index = chunkEnd + 2
        }
        return nil
    }

    private static func splitTarget(_ target: String) -> (String, [String: String]) {
        guard let questionMark = target.firstIndex(of: "?") else {
            return (target.removingPercentEncoding ?? target, [:])
        }
        let path = String(target[..<questionMark])
        let queryString = String(target[target.index(after: questionMark)...])
        var query: [String: String] = [:]
        for pair in queryString.components(separatedBy: "&") where !pair.isEmpty {
            let kv = pair.components(separatedBy: "=")
            let key = kv[0].removingPercentEncoding ?? kv[0]
            let value = kv.count > 1 ? (kv[1].removingPercentEncoding ?? kv[1]) : ""
            query[key] = value
        }
        return (path.removingPercentEncoding ?? path, query)
    }
}

struct HTTPResponse {
    let status: String
    let contentType: String
    var extraHeaders: [String: String] = [:]

    func data(appending body: Data) -> Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        for (key, value) in extraHeaders {
            header += "\(key): \(value)\r\n"
        }
        header += "\r\n"

        var output = header.data(using: .utf8) ?? Data()
        output.append(body)
        return output
    }
}

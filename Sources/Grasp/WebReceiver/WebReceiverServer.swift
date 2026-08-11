//
//  WebReceiverServer.swift
//  Grasp
//
//  Created by Elmee on 01/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation
import Network
import AppKit
import NDHackery

@MainActor
class WebReceiverServer: ObservableObject {
    @Published var isListening = false
    @Published var webURL: String = ""

    private var listener: NWListener?
    private var port: UInt16 = 7456
    private let downloadPathProvider: () -> String
    private let onFileReceived: (String, Int64) -> Void
    var onURLChanged: ((String) -> Void)?

    init(downloadPathProvider: @escaping () -> String, onFileReceived: @escaping (String, Int64) -> Void, onURLChanged: ((String) -> Void)? = nil) {
        self.downloadPathProvider = downloadPathProvider
        self.onFileReceived = onFileReceived
        self.onURLChanged = onURLChanged
    }

    func start(port: UInt16 = 7456) {
        self.port = port
        stop()

        do {
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: nwPort)

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                        let localIP = self.getLocalIPAddress() ?? "127.0.0.1"
                        self.webURL = "http://\(localIP):\(self.port)"
                        self.onURLChanged?(self.webURL)
                        print("[Web Receiver] Listening on \(self.webURL)")
                    case .failed(let err):
                        print("[Web Receiver Error] Listener failed: \(err)")
                        self.isListening = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleConnection(connection)
                }
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            print("[Web Receiver Error] Failed to start NWListener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
        webURL = ""
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveHTTPData(connection: connection, buffer: Data())
    }

    private func receiveHTTPData(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            var currentBuffer = buffer
            if let d = data {
                currentBuffer.append(d)
            }

            let crlfCrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
            if let headerEndRange = currentBuffer.range(of: crlfCrlf) {
                let headerData = currentBuffer.subdata(in: 0..<headerEndRange.upperBound)
                if let headerString = String(data: headerData, encoding: .utf8) {
                    let contentLength = self.extractContentLength(from: headerString)
                    let totalExpected = headerEndRange.upperBound + contentLength
                    
                    if currentBuffer.count >= totalExpected || isComplete {
                        self.processHTTPRequest(connection: connection, rawData: currentBuffer, headerString: headerString)
                        return
                    }
                }
            }

            if !isComplete && error == nil {
                self.receiveHTTPData(connection: connection, buffer: currentBuffer)
            } else {
                if !currentBuffer.isEmpty, let headerEndRange = currentBuffer.range(of: crlfCrlf),
                   let headerString = String(data: currentBuffer.subdata(in: 0..<headerEndRange.upperBound), encoding: .utf8) {
                    self.processHTTPRequest(connection: connection, rawData: currentBuffer, headerString: headerString)
                } else {
                    connection.cancel()
                }
            }
        }
    }

    private func extractContentLength(from header: String) -> Int {
        let lines = header.components(separatedBy: "\r\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let valStr = line.dropFirst(15).trimmingCharacters(in: .whitespaces)
                return Int(valStr) ?? 0
            }
        }
        return 0
    }

    private func processHTTPRequest(connection: NWConnection, rawData: Data, headerString: String) {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let method = parts[0]
        let rawPath = parts[1]
        let path = rawPath.removingPercentEncoding ?? rawPath

        if method == "GET" && path == "/" {
            sendResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: webHTML())
        } else if method == "GET" && path == "/api/files" {
            handleFileListAPI(connection: connection)
        } else if method == "GET" && path == "/api/clipboard" {
            handleClipboardGetAPI(connection: connection)
        } else if method == "POST" && path == "/api/clipboard" {
            handleClipboardPostAPI(connection: connection, rawData: rawData, headerString: headerString)
        } else if method == "GET" && path.hasPrefix("/download/") {
            let filename = String(path.dropFirst("/download/".count))
            handleFileDownload(connection: connection, filename: filename)
        } else if method == "POST" && path == "/upload" {
            handleFileUpload(connection: connection, rawData: rawData, headerString: headerString)
        } else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
        }
    }

    private func handleFileListAPI(connection: NWConnection) {
        let downloadDir = downloadPathProvider()
        let fm = FileManager.default
        var result: [[String: Any]] = []

        if let files = try? fm.contentsOfDirectory(atPath: downloadDir) {
            for file in files where !file.hasPrefix(".") {
                let fullPath = (downloadDir as NSString).appendingPathComponent(file)
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? Int64 {
                    let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                    result.append(["name": file, "size": size, "date": Int64(modDate)])
                }
            }
        }

        result.sort { ($0["date"] as? Int64 ?? 0) > ($1["date"] as? Int64 ?? 0) }

        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: jsonString)
        } else {
            sendResponse(connection: connection, status: "500 Internal Server Error", body: "[]")
        }
    }

    private func handleClipboardGetAPI(connection: NWConnection) {
        let text = DispatchQueue.main.sync {
            NSPasteboard.general.string(forType: .string) ?? ""
        }
        let dict = ["text": text]
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: jsonString)
        } else {
            sendResponse(connection: connection, status: "500 Internal Server Error", body: "{}")
        }
    }

    private func handleClipboardPostAPI(connection: NWConnection, rawData: Data, headerString: String) {
        let crlfCrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
        if let headerEndRange = rawData.range(of: crlfCrlf) {
            let bodyData = rawData.subdata(in: headerEndRange.upperBound..<rawData.count)
            if let text = String(data: bodyData, encoding: .utf8) {
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    
                    let center = UNUserNotificationCenter.current()
                    let content = UNMutableNotificationContent()
                    content.title = "Clipboard Synced 📋"
                    content.body = "Text copied from Web Hub to Mac clipboard!"
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    center.add(request, withCompletionHandler: nil)
                }
                sendResponse(connection: connection, status: "200 OK", contentType: "text/plain", body: "OK")
                return
            }
        }
        sendResponse(connection: connection, status: "400 Bad Request", body: "Invalid text")
    }

    private func handleFileDownload(connection: NWConnection, filename: String) {
        let downloadDir = downloadPathProvider()
        let cleanName = (filename as NSString).lastPathComponent
        let filePath = (downloadDir as NSString).appendingPathComponent(cleanName)

        guard FileManager.default.fileExists(atPath: filePath),
              let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            sendResponse(connection: connection, status: "404 Not Found", body: "File Not Found")
            return
        }

        let encodedName = cleanName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanName
        let responseHeaders = """
        HTTP/1.1 200 OK\r
        Content-Type: application/octet-stream\r
        Content-Length: \(fileData.count)\r
        Content-Disposition: attachment; filename="\(cleanName)"; filename*=UTF-8''\(encodedName)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r

        """

        var responseData = responseHeaders.data(using: .utf8) ?? Data()
        responseData.append(fileData)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func handleFileUpload(connection: NWConnection, rawData: Data, headerString: String) {
        var boundary = ""
        if let boundaryRange = headerString.range(of: "boundary=") {
            boundary = String(headerString[boundaryRange.upperBound...]).components(separatedBy: "\r\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
                boundary = String(boundary.dropFirst().dropLast())
            }
        }

        if let extracted = extractPayloadData(from: rawData, boundary: boundary) {
            let downloadDir = downloadPathProvider()
            try? FileManager.default.createDirectory(atPath: downloadDir, withIntermediateDirectories: true)
            let targetPath = (downloadDir as NSString).appendingPathComponent(extracted.filename)
            
            do {
                try extracted.fileData.write(to: URL(fileURLWithPath: targetPath))
                print("[Web Receiver] File saved successfully: \(targetPath) (\(extracted.fileData.count) bytes)")
                onFileReceived(extracted.filename, Int64(extracted.fileData.count))
                sendResponse(connection: connection, status: "200 OK", body: "OK")
                return
            } catch {
                print("[Web Receiver Error] Failed to write file: \(error)")
            }
        }

        sendResponse(connection: connection, status: "400 Bad Request", body: "Upload Error")
    }

    private func extractPayloadData(from rawData: Data, boundary: String) -> (filename: String, fileData: Data)? {
        guard !boundary.isEmpty,
              let boundaryData = ("--" + boundary).data(using: .utf8),
              let crlfCrlfData = "\r\n\r\n".data(using: .utf8) else {
            return ("received_web_file_\(Int(Date().timeIntervalSince1970))", rawData)
        }

        guard let firstBoundaryRange = rawData.range(of: boundaryData) else { return nil }
        let bodyFromBoundary = rawData.subdata(in: firstBoundaryRange.upperBound..<rawData.count)

        guard let subHeaderEndRange = bodyFromBoundary.range(of: crlfCrlfData) else { return nil }
        let subHeaderData = bodyFromBoundary.subdata(in: 0..<subHeaderEndRange.lowerBound)
        let subHeaderString = String(data: subHeaderData, encoding: .utf8) ?? ""

        var filename = "received_web_file_\(Int(Date().timeIntervalSince1970))"
        if let range = subHeaderString.range(of: "filename=\"") {
            let sub = subHeaderString[range.upperBound...]
            if let endRange = sub.range(of: "\"") {
                filename = String(sub[..<endRange.lowerBound])
            }
        }

        let fileDataStart = subHeaderEndRange.upperBound
        let searchRange = fileDataStart..<bodyFromBoundary.count
        guard let nextBoundaryRange = bodyFromBoundary.range(of: boundaryData, options: [], in: searchRange) else {
            var fileDataEnd = bodyFromBoundary.count
            if fileDataEnd >= 2 && bodyFromBoundary[fileDataEnd - 2] == 0x0D && bodyFromBoundary[fileDataEnd - 1] == 0x0A {
                fileDataEnd -= 2
            }
            let fileData = bodyFromBoundary.subdata(in: fileDataStart..<fileDataEnd)
            return (filename, fileData)
        }

        var fileDataEnd = nextBoundaryRange.lowerBound
        if fileDataEnd >= 2 && bodyFromBoundary[fileDataEnd - 2] == 0x0D && bodyFromBoundary[fileDataEnd - 1] == 0x0A {
            fileDataEnd -= 2
        }

        let fileData = bodyFromBoundary.subdata(in: fileDataStart..<fileDataEnd)
        return (filename, fileData)
    }

    private func sendResponse(connection: NWConnection, status: String, contentType: String = "text/plain", body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let responseHeaders = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r

        """
        var responseData = responseHeaders.data(using: .utf8) ?? Data()
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func getLocalIPAddress() -> String? {
        var fallbackAddress: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP | IFF_RUNNING)) != 0 && (flags & IFF_LOOPBACK) == 0 {
                if addr.sa_family == UInt8(AF_INET) {
                    let name = String(cString: ptr.pointee.ifa_name)
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if name.hasPrefix("en") {
                            freeifaddrs(ifaddr)
                            return ip
                        } else if fallbackAddress == nil {
                            fallbackAddress = ip
                        }
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        return fallbackAddress
    }

    private func webHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Grasp — Cross-Platform File Hub</title>
            <style>
                :root { --bg: #0b0f19; --card: #151c2c; --primary: #4f46e5; --accent: #06b6d4; --text: #f8fafc; --muted: #94a3b8; }
                * { box-sizing: border-box; }
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--text); display: flex; flex-direction: column; align-items: center; min-height: 100vh; margin: 0; padding: 24px 16px; }
                .container { max-width: 520px; width: 100%; display: flex; flex-direction: column; gap: 20px; }
                .card { background: var(--card); border-radius: 20px; padding: 24px; border: 1px solid rgba(255,255,255,0.08); box-shadow: 0 15px 30px rgba(0,0,0,0.4); }
                .header { text-align: center; }
                .logo-bar { width: 56px; height: 56px; display: inline-flex; align-items: center; justify-content: center; margin-bottom: 10px; filter: drop-shadow(0 4px 12px rgba(79,70,229,0.4)); }
                .logo-bar svg { width: 48px; height: 48px; }
                h1 { font-size: 20px; margin: 0 0 4px; font-weight: 700; }
                p { color: var(--muted); font-size: 13px; margin: 0; }
                .drop-zone { border: 2px dashed rgba(6,182,212,0.4); border-radius: 16px; padding: 28px 16px; background: rgba(6,182,212,0.03); cursor: pointer; text-align: center; transition: all 0.2s; }
                .drop-zone:hover { background: rgba(6,182,212,0.08); border-color: var(--accent); }
                .btn { background: linear-gradient(135deg, var(--primary), var(--accent)); color: white; border: none; padding: 10px 20px; border-radius: 10px; font-size: 13px; font-weight: 600; cursor: pointer; margin-top: 10px; }
                input[type="file"] { display: none; }
                .status { margin-top: 12px; font-size: 13px; color: #22c55e; font-weight: 600; text-align: center; }
                .section-title { font-size: 14px; font-weight: 700; margin-bottom: 12px; display: flex; justify-content: space-between; align-items: center; }
                .file-list { display: flex; flex-direction: column; gap: 8px; max-height: 220px; overflow-y: auto; }
                .file-item { display: flex; align-items: center; justify-content: space-between; padding: 10px 14px; background: rgba(255,255,255,0.04); border-radius: 12px; border: 1px solid rgba(255,255,255,0.05); }
                .file-info { display: flex; flex-direction: column; gap: 2px; }
                .file-name { font-size: 13px; font-weight: 600; word-break: break-all; }
                .file-meta { font-size: 11px; color: var(--muted); }
                .dl-btn { background: rgba(255,255,255,0.1); color: white; text-decoration: none; padding: 6px 12px; border-radius: 8px; font-size: 12px; font-weight: 600; transition: background 0.2s; }
                .dl-btn:hover { background: var(--accent); }
                .cli-box { background: #070a11; border-radius: 12px; padding: 12px; font-family: monospace; font-size: 11px; color: #38bdf8; word-break: break-all; border: 1px solid rgba(255,255,255,0.05); }
                .tabs { display: flex; gap: 6px; margin-bottom: 8px; }
                .tab-btn { background: none; border: none; color: var(--muted); font-size: 11px; font-weight: 600; cursor: pointer; padding: 4px 8px; border-radius: 6px; }
                .tab-btn.active { background: rgba(255,255,255,0.1); color: white; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="card header">
                    <div class="logo-bar">
                        <svg width="48" height="48" viewBox="0 0 24 24" fill="none">
                            <defs>
                                <linearGradient id="barGrad" x1="0" y1="0" x2="24" y2="24" gradientUnits="userSpaceOnUse">
                                    <stop offset="0%" stop-color="#4f46e5"/>
                                    <stop offset="100%" stop-color="#06b6d4"/>
                                </linearGradient>
                            </defs>
                            <path d="M 13.5 7.5 C 16.538 7.5 19 9.962 19 13 C 19 16.038 16.538 18.5 13.5 18.5 C 10.462 18.5 8 16.038 8 13 M 8 13 L 15 13" stroke="url(#barGrad)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
                            <path d="M 10.5 16.5 C 7.462 16.5 5 14.038 5 11 C 5 7.962 7.462 5.5 10.5 5.5 C 13.538 5.5 16 7.962 16 11" stroke="#06b6d4" stroke-opacity="0.6" stroke-width="2.2" stroke-linecap="round"/>
                        </svg>
                    </div>
                    <h1>Grasp File Hub</h1>
                    <p>Cross-Platform Sharing for Android, iPhone, Windows & Linux</p>
                </div>

                <div class="card">
                    <div class="section-title">📤 Upload Files to Mac</div>
                    <div class="drop-zone" onclick="document.getElementById('f').click()">
                        <div style="font-size: 14px; font-weight: 600; margin-bottom: 4px;">Click or Drag Files Here</div>
                        <div style="font-size: 12px; color: var(--muted);">Supports photos, videos, documents & archives</div>
                        <button class="btn" type="button">Choose Files</button>
                        <input type="file" id="f" multiple onchange="upload(this.files)">
                    </div>
                    <div class="status" id="s"></div>
                </div>

                <div class="card">
                    <div class="section-title">
                        <span>📥 Download Shared Files</span>
                        <span style="font-size: 11px; color: var(--muted);" id="file-count">Loading...</span>
                    </div>
                    <div class="file-list" id="fl">
                        <div style="text-align: center; color: var(--muted); font-size: 12px; padding: 12px;">Fetching files...</div>
                    </div>
                </div>

                <div class="card">
                    <div class="section-title">💻 Terminal CLI Commands (Windows / Linux)</div>
                    <div class="tabs">
                        <button class="tab-btn active" onclick="showCli('linux')">Linux / macOS (curl)</button>
                        <button class="tab-btn" onclick="showCli('win')">Windows (PowerShell)</button>
                    </div>
                    <div class="cli-box" id="cli-cmd">curl -F "file=@photo.jpg" http://' + window.location.host + '/upload</div>
                </div>
            </div>

            <script>
                function upload(files) {
                    if (!files || files.length === 0) return;
                    const status = document.getElementById('s');
                    status.innerText = "Uploading " + files[0].name + "...";
                    const formData = new FormData();
                    formData.append('file', files[0]);
                    fetch('/upload', { method: 'POST', body: formData })
                        .then(res => {
                            if (res.ok) {
                                status.innerText = "✓ File Uploaded Successfully!";
                                loadFiles();
                            } else {
                                status.innerText = "✕ Upload Failed!";
                            }
                        })
                        .catch(err => status.innerText = "✕ Upload Error: " + err);
                }

                function formatSize(bytes) {
                    if (bytes < 1024) return bytes + ' B';
                    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
                    return (bytes / 1048576).toFixed(1) + ' MB';
                }

                function loadFiles() {
                    fetch("/api/files")
                        .then(r => r.json())
                        .then(files => {
                            const fl = document.getElementById("fl");
                            const count = document.getElementById("file-count");
                            count.innerText = files.length + " files";
                            if (files.length === 0) {
                                fl.innerHTML = '<div style="text-align: center; color: var(--muted); font-size: 12px; padding: 12px;">No files available yet.</div>';
                                return;
                            }
                            fl.innerHTML = files.map(f => `
                                <div class="file-item">
                                    <div class="file-info">
                                        <div class="file-name">${f.name}</div>
                                        <div class="file-meta">${formatSize(f.size)}</div>
                                    </div>
                                    <a class="dl-btn" href="/download/${encodeURIComponent(f.name)}" download="${f.name}">Download</a>
                                </div>
                            `).join("");
                        })
                        .catch(e => console.error(e));
                }

                function showCli(os) {
                    const host = window.location.host;
                    const box = document.getElementById("cli-cmd");
                    const btns = document.querySelectorAll(".tab-btn");
                    btns.forEach(b => b.classList.remove("active"));
                    if (os === 'linux') {
                        btns[0].classList.add("active");
                        box.innerText = 'curl -F "file=@filename.zip" http://' + host + '/upload';
                    } else {
                        btns[1].classList.add("active");
                        box.innerText = 'Invoke-RestMethod -Uri "http://' + host + '/upload" -Method Post -InFile "filename.zip"';
                    }
                }

                loadFiles();
                setInterval(loadFiles, 5000);
            </script>
        </body>
        </html>
        """
    }
}


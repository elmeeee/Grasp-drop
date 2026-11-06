//
//  OtterDiscovery.swift
//  Otter
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation
import Darwin

@MainActor
final class OtterDiscovery: ObservableObject {
    @Published private(set) var peers: [OtterPeer] = []

    private var info: OtterDeviceInfo
    private var httpsSession: URLSession
    private var udpSocket: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var announceTimer: DispatchSourceTimer?

    init(info: OtterDeviceInfo) {
        self.info = info
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        self.httpsSession = URLSession(
            configuration: config, delegate: SelfSignedDelegate(), delegateQueue: nil)
    }

    func updateInfo(_ newInfo: OtterDeviceInfo) {
        self.info = newInfo
    }

    func start() {
        openMulticastSocket()
        announce(initial: true)

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.announce(initial: false) }
        }
        timer.resume()
        announceTimer = timer
    }

    func stop() {
        announceTimer?.cancel()
        announceTimer = nil
        readSource?.cancel()
        readSource = nil
        if udpSocket >= 0 {
            close(udpSocket)
            udpSocket = -1
        }
    }

    // MARK: - Multicast socket

    private func openMulticastSocket() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            OtterLog.write("discovery: socket() failed")
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = OtterProtocol.defaultPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else {
            OtterLog.write("discovery: bind() failed errno=\(errno)")
            close(fd)
            return
        }

        var membership = ip_mreq()
        membership.imr_multiaddr.s_addr = inet_addr(OtterProtocol.multicastGroup)
        membership.imr_interface.s_addr = INADDR_ANY
        let joinResult = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership,
                   socklen_t(MemoryLayout<ip_mreq>.size))
        OtterLog.write("discovery: multicast socket ready (join=\(joinResult))")

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            self?.readPending(fd: fd)
        }
        source.resume()
        readSource = source
        udpSocket = fd
    }

    private nonisolated func readPending(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var from = sockaddr_in()
        var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)

        let received = withUnsafeMutablePointer(to: &from) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLength)
            }
        }
        guard received > 0 else { return }
        let data = Data(buffer[0..<received])
        let host = String(cString: inet_ntoa(from.sin_addr))

        Task { @MainActor in
            self.handleAnnouncement(data, from: host)
        }
    }

    private func handleAnnouncement(_ data: Data, from host: String) {
        guard let incoming = try? JSONDecoder().decode(OtterDeviceInfo.self, from: data) else {
            return
        }
        guard !incoming.fingerprint.isEmpty,
              incoming.fingerprint != info.fingerprint else { return }

        merge(OtterPeer(info: incoming, ip: host))
        if incoming.announce == true {
            Task { await register(to: host) }
        }
    }

    private func announce(initial: Bool) {
        guard udpSocket >= 0 else { return }
        var message = info
        message.announce = initial
        guard let payload = try? JSONEncoder().encode(message) else { return }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = OtterProtocol.defaultPort.bigEndian
        addr.sin_addr.s_addr = inet_addr(OtterProtocol.multicastGroup)

        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(udpSocket, (payload as NSData).bytes, payload.count, 0,
                       $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    // MARK: - HTTP register (two-way discovery)

    private func register(to host: String) async {
        guard !host.isEmpty else { return }
        guard let url = URL(string:
            "https://\(host):\(OtterProtocol.defaultPort)/api/otter/v2/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(info)

        guard let (data, _) = try? await httpsSession.data(for: request),
              let peerInfo = try? JSONDecoder().decode(OtterDeviceInfo.self, from: data),
              peerInfo.fingerprint != info.fingerprint else { return }
        merge(OtterPeer(info: peerInfo, ip: host))
    }

    /// Legacy fallback: probe every host on the local /24 when multicast fails.
    func scanLocalSubnet() {
        guard let localIP = Self.localIPv4() else { return }
        let parts = localIP.split(separator: ".")
        guard parts.count == 4 else { return }
        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])."

        for host in 1...254 where "\(prefix)\(host)" != localIP {
            Task { await register(to: "\(prefix)\(host)") }
        }
    }

    private func merge(_ peer: OtterPeer) {
        if let index = peers.firstIndex(where: { $0.id == peer.id }) {
            if peers[index] != peer { peers[index] = peer }
        } else {
            peers.append(peer)
            OtterLog.write("Found device: \(peer.displayName) (\(peer.ip))")
        }
    }

    static func localIPv4() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            if (flags & (IFF_UP | IFF_RUNNING)) != 0 && (flags & IFF_LOOPBACK) == 0,
               addr.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                               &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: host)
                    break
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}

/// Accepts the self-signed certificates used by LocalSend peers.
final class SelfSignedDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod
            == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

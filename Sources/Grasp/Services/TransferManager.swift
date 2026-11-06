//
//  TransferManager.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import AppKit
import Combine
import CoreBluetooth
import Foundation
import NDHackery
import UserNotifications

@MainActor
class TransferManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var isRunning = false
    @Published var visibilityMode: VisibilityMode = .everyone
    @Published var statusText = "Active & Visible to Everyone"
    @Published var deviceName: String = Host.current().localizedName ?? ""
    @Published var downloadPath: String =
        UserDefaults.standard.string(forKey: "GraspDownloadPath")
        ?? NSString(string: "~/Downloads/Grasp").expandingTildeInPath
    {
        didSet {
            UserDefaults.standard.set(downloadPath, forKey: "GraspDownloadPath")
        }
    }
    @Published var autoAccept: Bool = UserDefaults.standard.bool(forKey: "GraspAutoAccept") {
        didSet {
            UserDefaults.standard.set(autoAccept, forKey: "GraspAutoAccept")
        }
    }
    @Published var soundEnabled: Bool =
        UserDefaults.standard.object(forKey: "GraspSoundEnabled") == nil
        ? true : UserDefaults.standard.bool(forKey: "GraspSoundEnabled")
    {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: "GraspSoundEnabled")
        }
    }

    @Published var recentTransfers: [TransferItem] = []
    @Published var activeTransfer: ActiveTransfer?
    @Published var currentPendingTransfer: PendingTransfer?
    @Published var webURL: String = ""
    @Published var isGraspShareRunning = false
    @Published var nearbyPeers: [GraspPeer] = []

    weak var appDelegate: AnyObject?

    private var pendingRequests: [String: PendingTransfer] = [:]
    private var webServer: WebReceiverServer?
    private var centralManager: CBCentralManager?
    private var graspServer: GraspServer?
    private var graspDiscovery: GraspDiscovery?
    private var graspSender: GraspSender?
    private var graspInfo: GraspDeviceInfo?
    private var discoveryCancellable: AnyCancellable?

    override init() {
        super.init()
        UserDefaults.standard.removeObject(forKey: "GraspDeviceName")
        requestBluetoothPermission()
        ensureDownloadFolderExists()
        loadHistoryFromFolder()
        startEngine()
    }

    func requestBluetoothPermission() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[Grasp BLE] Bluetooth Authorized & Powered ON")
        case .poweredOff:
            print("[Grasp BLE] Bluetooth Powered OFF")
        default:
            break
        }
    }

    func toggleEngine(_ enable: Bool) {
        if enable {
            startEngine()
        } else {
            stopEngine()
        }
    }

    func setVisibility(_ mode: VisibilityMode) {
        self.visibilityMode = mode
        if mode == .off {
            statusText = "Receiver Disabled"
            stopEngine()
        } else {
            statusText = "Active & Visible to Everyone"
            startEngine()
        }
    }

    func startEngine() {
        guard !isRunning else { return }

        // Configure Native Quick Share NearbyConnectionManager
        NearbyConnectionManager.shared.mainAppDelegate = self
        NearbyConnectionManager.shared.becomeVisible()

        // Start Native WebReceiverServer
        let web = WebReceiverServer(
            downloadPathProvider: { [weak self] in
                self?.downloadPath ?? NSString(string: "~/Downloads/Grasp").expandingTildeInPath
            },
            onFileReceived: { [weak self] fileName, fileSize in
                Task { @MainActor [weak self] in
                    self?.handleFileReceived(fileName: fileName, fileSize: fileSize, isWeb: true)
                }
            },
            onURLChanged: { [weak self] url in
                Task { @MainActor [weak self] in
                    self?.webURL = url
                }
            }
        )
        web.start(port: 7456)
        self.webServer = web

        startGraspShare()

        self.isRunning = true
        self.statusText = "Active & Visible to Everyone"
        print("[Grasp Engine] Quick Share & Web Receiver Engines Started!")
    }

    // MARK: - Grasp Share v2 Layer

    private func startGraspShare() {
        GraspLog.write("startGraspShare() entered, downloadPath=\(downloadPath)")
        let stateDir = URL(fileURLWithPath: downloadPath).appendingPathComponent(".grasp")
        guard let identity = GraspIdentity.loadOrCreate(stateDirectory: stateDir) else {
            GraspLog.write("could not create identity")
            return
        }
        GraspLog.write("identity fingerprint=\(identity.fingerprint)")

        let info = GraspDeviceInfo(
            alias: deviceName,
            version: GraspProtocol.protocolVersion,
            deviceModel: "Mac",
            deviceType: GraspProtocol.deviceDesktop,
            fingerprint: identity.fingerprint,
            port: Int(GraspProtocol.defaultPort),
            protocol: GraspProtocol.schemeHTTPS,
            download: true)
        self.graspInfo = info

        let server = GraspServer(
            identity: identity,
            info: info,
            filesDirectory: { [weak self] in
                self?.downloadPath ?? NSString(string: "~/Downloads/Grasp").expandingTildeInPath
            },
            onFileReceived: { [weak self] name, size in
                Task { @MainActor in
                    self?.handleFileReceived(fileName: name, fileSize: size, isWeb: true)
                }
            })
        server.start()
        graspServer = server

        let discovery = GraspDiscovery(info: info)
        discoveryCancellable = discovery.$peers
            .receive(on: RunLoop.main)
            .sink { [weak self] peers in
                self?.nearbyPeers = peers
            }
        discovery.start()
        graspDiscovery = discovery

        graspSender = GraspSender(info: info)
        isGraspShareRunning = true
    }

    private func stopGraspShare() {
        graspServer?.stop()
        graspServer = nil
        graspDiscovery?.stop()
        graspDiscovery = nil
        graspSender = nil
        discoveryCancellable = nil
        isGraspShareRunning = false
    }

    func scanForNearbyPeers() {
        graspDiscovery?.scanLocalSubnet()
    }

    func sendNearbyFiles(urls: [URL], to peer: GraspPeer) {
        guard let sender = graspSender else { return }
        Task {
            do {
                try await sender.send(files: urls, to: peer) { _ in }
                handleFileReceived(
                    fileName: urls.first?.lastPathComponent ?? "File",
                    fileSize: 0, isWeb: true)
            } catch {
                print("[LocalSend] Send failed: \(error.localizedDescription)")
            }
        }
    }

    func selectAndSendNearbyFiles(to peer: GraspPeer) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Send to \(peer.displayName)"
        if panel.runModal() == .OK {
            sendNearbyFiles(urls: panel.urls, to: peer)
        }
    }

    func stopEngine() {
        webServer?.stop()
        webServer = nil
        stopGraspShare()
        isRunning = false
        statusText = "Stopped"
    }

    func handleFileReceived(fileName: String, fileSize: Int64, isWeb: Bool) {
        let fullPath = (downloadPath as NSString).appendingPathComponent(fileName)
        let item = TransferItem(
            id: UUID(),
            fileName: fileName,
            filePath: fullPath,
            fileSize: fileSize,
            timestamp: Date(),
            senderDevice: isWeb ? "Web Browser" : "Android Device",
            isWebUpload: isWeb
        )
        if !recentTransfers.contains(where: { $0.filePath == item.filePath }) {
            recentTransfers.insert(item, at: 0)
        }
        if soundEnabled {
            NSSound(named: "Glass")?.play()
        }
    }

    // MARK: - Transfer Actions (Triggered by Native macOS Push Notifications)

    func acceptPendingTransferByID(_ id: String) {
        guard
            let target = pendingRequests.removeValue(forKey: id)
                ?? (currentPendingTransfer?.id == id ? currentPendingTransfer : nil)
        else { return }
        if currentPendingTransfer?.id == id {
            currentPendingTransfer = nil
        }
        if soundEnabled {
            NSSound(named: "Pop")?.play()
        }
        self.activeTransfer = ActiveTransfer(
            id: target.id,
            fileName: target.fileName,
            bytesWritten: 0,
            totalBytes: target.fileSize,
            speedBps: 0,
            status: "receiving"
        )
        NearbyConnectionManager.shared.submitUserConsent(transferID: target.id, accept: true)
    }

    func declinePendingTransferByID(_ id: String) {
        pendingRequests.removeValue(forKey: id)
        if currentPendingTransfer?.id == id {
            currentPendingTransfer = nil
        }
        if soundEnabled {
            NSSound(named: "Basso")?.play()
        }
        self.activeTransfer = nil
        NearbyConnectionManager.shared.submitUserConsent(transferID: id, accept: false)
    }

    func cancelActiveTransfer() {
        if let active = activeTransfer {
            NearbyConnectionManager.shared.submitUserConsent(transferID: active.id, accept: false)
        }
        self.activeTransfer = nil
    }

    func selectDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Save Directory"

        if panel.runModal() == .OK, let url = panel.url {
            self.downloadPath = url.path
            ensureDownloadFolderExists()
            loadHistoryFromFolder()
        }
    }

    func openDownloadFolder() {
        ensureDownloadFolderExists()
        NSWorkspace.shared.open(URL(fileURLWithPath: downloadPath))
    }

    func selectAndSendFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Share File(s)"

        if panel.runModal() == .OK {
            sendFiles(urls: panel.urls)
        }
    }

    func sendFiles(urls: [URL]) {
        ensureDownloadFolderExists()
        let fm = FileManager.default

        for url in urls {
            let filename = url.lastPathComponent
            let targetPath = (downloadPath as NSString).appendingPathComponent(filename)

            if url.path != targetPath {
                try? fm.removeItem(atPath: targetPath)
                try? fm.copyItem(atPath: url.path, toPath: targetPath)
            }

            if let attrs = try? fm.attributesOfItem(atPath: targetPath),
               let size = attrs[.size] as? Int64 {
                handleFileReceived(fileName: filename, fileSize: size, isWeb: true)
            }
        }
    }

    func openFileInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clearHistory() {
        recentTransfers.removeAll()
    }

    private func ensureDownloadFolderExists() {
        try? FileManager.default.createDirectory(
            atPath: downloadPath, withIntermediateDirectories: true)
    }

    private func loadHistoryFromFolder() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: downloadPath) else { return }

        var loaded: [TransferItem] = []
        for f in files.prefix(20) {
            if f.hasPrefix(".") { continue }
            let fullPath = (downloadPath as NSString).appendingPathComponent(f)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                let size = attrs[.size] as? Int64,
                let date = attrs[.modificationDate] as? Date
            {
                loaded.append(
                    TransferItem(
                        id: UUID(),
                        fileName: f,
                        filePath: fullPath,
                        fileSize: size,
                        timestamp: date,
                        senderDevice: "Received File",
                        isWebUpload: false
                    ))
            }
        }
        loaded.sort(by: { $0.timestamp > $1.timestamp })
        self.recentTransfers = loaded
    }
}

// MARK: - MainAppDelegate

extension TransferManager: MainAppDelegate {
    nonisolated func obtainUserConsent(
        for transfer: TransferMetadata, from device: RemoteDeviceInfo
    ) {
        Task { @MainActor in
            let req = PendingTransfer(
                id: transfer.id,
                deviceName: device.name,
                pinCode: transfer.pinCode ?? "0000",
                fileName: transfer.files.first?.name ?? "File",
                fileSize: transfer.files.first?.size ?? 0,
                fileCount: transfer.files.count
            )

            self.pendingRequests[req.id] = req
            self.currentPendingTransfer = req

            if self.soundEnabled {
                if !(NSSound(named: "Ping")?.play() ?? false) {
                    NSSound.beep()
                }
            }

            if let delegate = self.appDelegate as? AppDelegate {
                delegate.showPanel()
            }

            if self.autoAccept {
                self.acceptPendingTransferByID(req.id)
            } else {
                self.sendIncomingNotification(req)
            }
        }
    }

    nonisolated func incomingTransfer(id: String, didFinishWith error: Error?) {
        Task { @MainActor in
            if error == nil {
                let fname = self.activeTransfer?.fileName ?? "Received_File"
                let size = self.activeTransfer?.totalBytes ?? 0
                self.handleFileReceived(fileName: fname, fileSize: size, isWeb: false)
            }
            self.activeTransfer = nil
            self.pendingRequests.removeValue(forKey: id)
        }
    }

    private func sendIncomingNotification(_ transfer: PendingTransfer) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Quick Share: \(transfer.deviceName)"
        content.subtitle = "\(transfer.fileName) (\(transfer.formattedSize))"
        content.body = "PIN Verification: \(transfer.pinCode)"
        content.sound = .default
        content.categoryIdentifier = "GRASP_TRANSFER_REQUEST"

        NDNotificationCenterHackery.removeDefaultAction(content)

        let request = UNNotificationRequest(identifier: transfer.id, content: content, trigger: nil)
        center.add(request) { error in
            if let error = error {
                print("[Grasp] Failed to schedule incoming transfer notification: \(error)")
            } else {
                print(
                    "[Grasp] Successfully scheduled incoming transfer notification for \(transfer.fileName)"
                )
            }
        }
    }
}

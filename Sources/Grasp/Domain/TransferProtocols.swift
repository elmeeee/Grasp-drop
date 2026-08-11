//
//  TransferProtocols.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation

/// Domain abstraction for local file storage operations.
public protocol FileStorageProtocol {
    var downloadDirectoryPath: String { get }
    func ensureFolderExists()
    func listSavedFiles() -> [URL]
    func openDownloadsFolder()
}

/// Domain abstraction for Web Receiver HTTP Server operations.
public protocol WebReceiverServiceProtocol {
    var isListening: Bool { get }
    var localServerURL: String { get }
    func start(downloadPath: String, onFileReceived: @escaping (String) -> Void)
    func stop()
}

/// Domain abstraction for Google Quick Share / Nearby Share operations.
public protocol NearbyTransferProtocol {
    var isAdvertising: Bool { get }
    func startAdvertising(deviceName: String)
    func stopAdvertising()
}

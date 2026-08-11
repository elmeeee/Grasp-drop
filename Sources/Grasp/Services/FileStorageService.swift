//
//  FileStorageService.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import AppKit
import Foundation

public final class FileStorageService: FileStorageProtocol {
    public static let shared = FileStorageService()
    
    public var downloadDirectoryPath: String {
        return UserDefaults.standard.string(forKey: "GraspDownloadPath")
            ?? NSString(string: "~/Downloads/Grasp").expandingTildeInPath
    }
    
    public init() {}
    
    public func ensureFolderExists() {
        let path = downloadDirectoryPath
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    public func listSavedFiles() -> [URL] {
        let url = URL(fileURLWithPath: downloadDirectoryPath)
        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return []
        }
        return files.sorted { u1, u2 in
            let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return d1 > d2
        }
    }
    
    public func openDownloadsFolder() {
        ensureFolderExists()
        let url = URL(fileURLWithPath: downloadDirectoryPath)
        NSWorkspace.shared.open(url)
    }
}

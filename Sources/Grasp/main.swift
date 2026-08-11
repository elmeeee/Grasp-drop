//
//  main.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Cocoa
import SwiftUI
import UserNotifications
import NDHackery

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

class MenuBarPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = contentView
    }

    override var canBecomeKey: Bool {
        return true
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var panel: MenuBarPanel!
    var transferManager: TransferManager!
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize State & Engine Manager
        transferManager = TransferManager()
        transferManager.appDelegate = self

        // Create Control Center Style Panel
        let hostingController = NSHostingController(rootView: MenuBarView(transferManager: transferManager))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 340, height: 380)
        panel = MenuBarPanel(contentView: hostingController.view)

        // Setup Native Status Item in macOS Menu Bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            var iconImg: NSImage?
            if let barIconUrl = Bundle.main.url(forResource: "BarIcon", withExtension: "png"),
               let customImg = NSImage(contentsOf: barIconUrl) {
                iconImg = customImg
            } else if let customImg = NSImage(named: "BarIcon") {
                iconImg = customImg
            } else {
                iconImg = NSImage(systemSymbolName: "arrow.down.to.line.circle.fill", accessibilityDescription: "Grasp")
            }
            iconImg?.isTemplate = true
            button.image = iconImg
            button.toolTip = "Grasp — Quick Share & Web Receiver"
            button.action = #selector(togglePanel)
            button.target = self
        }

        setupNotificationCategories()
        setupGlobalHotkey()
    }

    private func setupGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 5 && event.modifierFlags.contains([.command, .shift]) {
                DispatchQueue.main.async {
                    self?.togglePanel(nil)
                }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 5 && event.modifierFlags.contains([.command, .shift]) {
                DispatchQueue.main.async {
                    self?.togglePanel(nil)
                }
                return nil
            }
            return event
        }
    }

    @objc func togglePanel(_ sender: Any?) {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let buttonScreenFrame = buttonWindow.convertToScreen(button.frame)
        let panelSize = panel.frame.size

        // Calculate X position so panel is horizontally aligned with status item button
        var x = buttonScreenFrame.midX - (panelSize.width / 2.0)

        if let screen = buttonWindow.screen {
            let screenVisible = screen.visibleFrame
            if x + panelSize.width > screenVisible.maxX - 8 {
                x = screenVisible.maxX - panelSize.width - 8
            }
            if x < screenVisible.minX + 8 {
                x = screenVisible.minX + 8
            }
        }

        // Position panel 4px directly beneath the status bar item
        let y = buttonScreenFrame.minY - panelSize.height - 4

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Monitor global clicks outside panel to automatically close it
        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePanel()
            }
        }
    }

    func closePanel() {
        panel.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func setupNotificationCategories() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let acceptAction = UNNotificationAction(
            identifier: "ACCEPT_ACTION",
            title: "Accept",
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: "DECLINE_ACTION",
            title: "Decline",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: "GRASP_TRANSFER_REQUEST",
            actions: [acceptAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("[Grasp] Notification permission: \(granted)")
        }
    }

    // Handle incoming user notification clicks & actions
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let transferID = response.notification.request.identifier
        Task { @MainActor in
            switch action {
            case "ACCEPT_ACTION":
                self.transferManager.acceptPendingTransferByID(transferID)
            case "DECLINE_ACTION":
                self.transferManager.declinePendingTransferByID(transferID)
            default:
                // Default tap on notification banner accepts transfer
                self.transferManager.acceptPendingTransferByID(transferID)
            }
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        Task { @MainActor in
            self.transferManager?.stopEngine()
        }
    }
}


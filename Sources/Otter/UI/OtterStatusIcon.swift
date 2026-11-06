//
//  OtterStatusIcon.swift
//  Otter
//
//  Menu bar status icon that reflects the current Otter state.
//

import AppKit

/// The visual states shown in the menu bar.
enum OtterStatusState: Equatable {
    case idle          // Visible and running, nothing happening
    case waiting       // Waiting for a connection or a consent decision
    case transferring  // Sending or receiving a file
    case success       // A transfer just finished (shown briefly)
}

/// Chooses and applies the status item image.
@MainActor
final class OtterStatusIcon {
    private weak var button: NSStatusBarButton?
    private var successResetWork: DispatchWorkItem?
    private(set) var state: OtterStatusState = .idle

    init(button: NSStatusBarButton) {
        self.button = button
        apply(.idle)
    }

    /// Moves to a new state. `success` reverts to `idle` after a short delay.
    func set(_ newState: OtterStatusState) {
        successResetWork?.cancel()
        successResetWork = nil
        apply(newState)

        if newState == .success {
            let work = DispatchWorkItem { [weak self] in
                self?.apply(.idle)
            }
            successResetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }
    }

    private func apply(_ newState: OtterStatusState) {
        state = newState
        button?.image = OtterStatusIcon.image(for: newState)
    }

    /// Loads the 1x/2x/3x menu bar image for a state. Falls back to the idle
    /// icon, then to an SF Symbol, so the item is never blank.
    static func image(for state: OtterStatusState) -> NSImage? {
        let name: String
        switch state {
        case .idle: name = "idle"
        case .waiting: name = "waiting"
        case .transferring: name = "transferring"
        case .success: name = "success"
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        for suffix in ["", "@2x", "@3x"] {
            if let url = Bundle.main.url(forResource: "otter-status-\(name)\(suffix)", withExtension: "png"),
               let rep = NSImageRep(contentsOf: url) {
                rep.size = NSSize(width: 18, height: 18)
                image.addRepresentation(rep)
            }
        }

        if image.representations.isEmpty {
            return NSImage(systemSymbolName: "arrow.down.to.line.circle.fill", accessibilityDescription: "Otter")
        }

        // Full-colour artwork: keep the original colours instead of a template.
        image.isTemplate = false
        return image
    }
}

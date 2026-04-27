import Foundation
import AppKit
import QuartzCore

/// Toggles app-wide animation. In tests you typically want them off so
/// snapshots and assertions don't race transitions. See [ADR-009].
@MainActor
public enum PryAnimations {

    public private(set) static var enabled: Bool = true

    public static func setEnabled(_ on: Bool) {
        enabled = on
        if on {
            // Restore defaults — leave NSAnimationContext at its system value.
            CATransaction.setDisableActions(false)
            UserDefaults.standard.set(false, forKey: "NSGlobalDomain.NSAutomaticWindowAnimationsEnabled.disable")
        } else {
            // Disable Core Animation actions; SwiftUI honors this for many implicit animations.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.commit()
            // Disable AppKit window animations
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
            }
        }
    }
}

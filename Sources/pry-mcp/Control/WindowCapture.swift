import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Out-of-process window capture. Uses `CGWindowListCreateImage` to produce a
/// PNG of the frontmost window owned by the target PID.
///
/// This avoids the ScreenCaptureKit dance and works without extra entitlements,
/// at the cost of requiring Screen Recording permission on macOS 14+ for the
/// calling process when capturing windows of other apps.
public enum WindowCapture {

    public static func capturePNG(pid: pid_t) async -> Data? {
        guard let windowID = firstWindowID(forPID: pid) else { return nil }
        let opts: CGWindowListOption = [.optionIncludingWindow]
        guard let cg = CGWindowListCreateImage(.null, opts, windowID, [.boundsIgnoreFraming]) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    private static func firstWindowID(forPID pid: pid_t) -> CGWindowID? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for item in list {
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let number = item[kCGWindowNumber as String] as? CGWindowID,
                  let layer = item[kCGWindowLayer as String] as? Int, layer == 0
            else { continue }
            return number
        }
        return nil
    }
}

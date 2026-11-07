import AppKit
import ApplicationServices

struct ZoomMeetingDetector {
    private(set) var inMeeting = false
    private var consecutiveAbsences = 0

    // A failed AX read does not mean that the call ended.
    mutating func observe(_ titles: [String]?) -> Bool {
        guard let titles else { return false }
        let meetingVisible = titles.contains {
            let title = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["zoom meeting", "réunion zoom", "zoom webinar", "webinaire zoom"].contains(title)
        }
        if meetingVisible {
            consecutiveAbsences = 0
            guard !inMeeting else { return false }
            inMeeting = true
            return true
        }
        consecutiveAbsences = min(consecutiveAbsences + 1, 2)
        if consecutiveAbsences == 2 { inMeeting = false }
        return false
    }

    static func windowTitles() -> [String]? {
        guard AXIsProcessTrusted() else { return nil }
        guard let zoom = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first
        else { return [] }

        let app = AXUIElementCreateApplication(zoom.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else { return nil }

        var titles: [String] = []
        for window in windows {
            var title: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            if result == .cannotComplete { return nil }
            if let name = title as? String { titles.append(name) }
        }
        return titles
    }
}

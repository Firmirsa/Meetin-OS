import AppKit
import ApplicationServices

struct ZoomMeetingDetector {
    private(set) var arrivalID: UUID?
    private var consecutiveAbsences = 0
    var inMeeting: Bool { arrivalID != nil }

    // A failed AX read does not mean that the call ended.
    mutating func observe(_ titles: [String]?) -> Bool {
        guard let titles else { return false }
        if Self.hasMeetingWindow(titles) {
            consecutiveAbsences = 0
            guard !inMeeting else { return false }
            arrivalID = UUID()
            return true
        }
        consecutiveAbsences = min(consecutiveAbsences + 1, 2)
        if consecutiveAbsences == 2 { arrivalID = nil }
        return false
    }

    func isCurrentArrival(_ id: UUID, titles: [String]?) -> Bool {
        guard id == arrivalID, let titles else { return false }
        return Self.hasMeetingWindow(titles)
    }

    private static func hasMeetingWindow(_ titles: [String]) -> Bool {
        titles.contains {
            let title = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["zoom meeting", "réunion zoom", "zoom webinar", "webinaire zoom"].contains(title)
        }
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

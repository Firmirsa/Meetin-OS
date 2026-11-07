import AppKit
import ApplicationServices

// Les lectures AX peuvent attendre la réponse d’une autre app. Elles restent hors du thread d’interface.
actor MeetingAccessibility {
    private static let chrome = "com.google.Chrome"
    private static let enhancedUI = "AXEnhancedUserInterface" as CFString
    private var chromeElement: AXUIElement?
    private var chromePID: pid_t?

    func readAll(trackedMeet: String?) -> [MeetingSource: MeetingPresence] {
        Dictionary(uniqueKeysWithValues: MeetingSource.allCases.map { ($0, read($0, trackedKey: trackedMeet)) })
    }

    func read(_ source: MeetingSource, trackedKey: String? = nil) -> MeetingPresence {
        guard AXIsProcessTrusted() else { return .unknown }
        switch source {
        case .zoom: return zoom()
        case .meet: return meet(trackedRoom: trackedKey)
        case .whatsapp: return whatsApp()
        }
    }

    func stop() {
        if let chromeElement {
            AXUIElementSetAttributeValue(chromeElement, Self.enhancedUI, kCFBooleanFalse)
        }
        chromeElement = nil
        chromePID = nil
    }

    private func application(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    private func element(_ application: NSRunningApplication) -> AXUIElement {
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.12)
        return app
    }

    private func zoom() -> MeetingPresence {
        guard let running = application("us.zoom.xos") else { return .idle }
        guard let windows = value(element(running), kAXWindowsAttribute) as? [AXUIElement] else { return .unknown }
        var titles: [String] = []
        for window in windows.prefix(20) {
            let (status, title) = attribute(window, kAXTitleAttribute)
            if status == .cannotComplete { return .unknown }
            if let title = title as? String { titles.append(title) }
        }
        return MeetingSignals.zoom(titles)
    }

    private func meet(trackedRoom: String?) -> MeetingPresence {
        guard let running = application(Self.chrome) else {
            chromeElement = nil
            chromePID = nil
            return .idle
        }
        let app = element(running)
        if chromePID != running.processIdentifier {
            stop()
            chromePID = running.processIdentifier
            if AXUIElementSetAttributeValue(app, Self.enhancedUI, kCFBooleanTrue) == .success {
                chromeElement = app
            }
        }
        guard let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] else { return .unknown }
        var activeRoom: String?
        var sawTrackedPage = false
        var hiddenTrackedTab = false
        var uncertain = false
        let deadline = ContinuousClock.now + .milliseconds(450)
        for window in windows.prefix(12) {
            let result = walk(window, limit: 220, deadline: deadline) { node, role in
                if role == "AXWebArea" {
                    guard let rawURL = value(node, kAXURLAttribute),
                          let url = (rawURL as? URL) ?? (rawURL as? String).flatMap(URL.init(string:)),
                          let room = MeetingSignals.meetRoom(url) else { return .skip }
                    if room == trackedRoom { sawTrackedPage = true }
                    switch walk(node, limit: 650, deadline: deadline, visit: { child, childRole in
                        if childRole == "AXWebArea", !CFEqual(child, node) { return .skip }
                        if childRole == kAXButtonRole, enabled(child), MeetingSignals.meetHangUp(labels(child)) { return .match }
                        return .descend
                    }) {
                    case .match:
                        activeRoom = room
                        if trackedRoom == nil || room == trackedRoom { return .match }
                    case .incomplete: uncertain = true
                    case .complete: break
                    }
                    return .skip
                }
                if let trackedRoom, role == "AXTab" || role == "AXRadioButton",
                   labels(node).contains(where: { $0.contains(trackedRoom) }) { hiddenTrackedTab = true }
                return .descend
            }
            if result == .match, let activeRoom { return .active(activeRoom) }
            if result == .incomplete { uncertain = true }
        }
        if let activeRoom { return .active(activeRoom) }
        return uncertain || (hiddenTrackedTab && !sawTrackedPage) ? .unknown : .idle
    }

    private func whatsApp() -> MeetingPresence {
        guard let running = application("net.whatsapp.WhatsApp") else { return .idle }
        guard let windows = value(element(running), kAXWindowsAttribute) as? [AXUIElement] else { return .unknown }
        var uncertain = false
        let deadline = ContinuousClock.now + .milliseconds(350)
        for window in windows.prefix(12) {
            let endButton = walk(window, limit: 260, deadline: deadline) { node, role in
                if Self.isConversation(role) { return .skip }
                if role == kAXButtonRole, enabled(node), MeetingSignals.whatsAppHangUp(labels(node)) { return .match }
                return .descend
            }
            if endButton == .incomplete { uncertain = true }
            guard endButton == .match else { continue }
            let connected = walk(window, limit: 260, deadline: deadline) { node, role in
                if Self.isConversation(role) { return .skip }
                if role == kAXStaticTextRole {
                    let text = value(node, kAXValueAttribute) as? String ?? ""
                    if MeetingSignals.whatsAppConnected([text] + labels(node)) { return .match }
                }
                return .descend
            }
            if connected == .match { return .active("whatsapp") }
            if connected == .incomplete { uncertain = true }
        }
        return uncertain ? .unknown : .idle
    }

    private static func isConversation(_ role: String) -> Bool {
        ["AXList", "AXOutline", "AXTable", "AXScrollArea", "AXWebArea", "AXTextArea", "AXTextField"].contains(role)
    }

    private enum Visit { case descend, skip, match }
    private enum Scan { case complete, match, incomplete }

    private func walk(_ root: AXUIElement, limit: Int, deadline: ContinuousClock.Instant,
                      visit: (AXUIElement, String) -> Visit) -> Scan {
        var nodes = [root]
        var index = 0
        while index < nodes.count {
            guard index < limit, ContinuousClock.now < deadline else { return .incomplete }
            let node = nodes[index]
            index += 1
            let (status, role) = attribute(node, kAXRoleAttribute)
            if status == .cannotComplete { return .incomplete }
            guard let role = role as? String else { continue }
            switch visit(node, role) {
            case .match: return .match
            case .skip: continue
            case .descend:
                let (status, children) = attribute(node, kAXChildrenAttribute)
                if status == .cannotComplete { return .incomplete }
                if let children = children as? [AXUIElement], nodes.count <= limit {
                    nodes.append(contentsOf: children.prefix(limit + 1 - nodes.count))
                }
            }
        }
        return .complete
    }

    private func labels(_ node: AXUIElement) -> [String] {
        let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(node, names, [], &values) == .success else { return [] }
        return (values as? [Any] ?? []).compactMap { $0 as? String }
    }

    private func enabled(_ node: AXUIElement) -> Bool { (value(node, kAXEnabledAttribute) as? Bool) != false }

    private func value(_ node: AXUIElement, _ name: String) -> CFTypeRef? { attribute(node, name).1 }

    private func attribute(_ node: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(node, name as CFString, &value)
        return (status, value)
    }
}

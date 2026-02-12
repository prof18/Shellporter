import ApplicationServices
import Foundation

/// Snapshot of a single AX window's relevant attributes.
/// `windowSource` records which AX query found this window ("focused", "main", "windows[N]")
/// for diagnostics.
struct AXWindowSnapshot {
    let trusted: Bool
    let title: String?
    let document: String?
    let windowSource: String?
}

/// Reads window attributes (title, document path) from the macOS Accessibility API.
///
/// Window selection priority: focused > main > first in window list. The focused window
/// is preferred because when an IDE has multiple project windows open, the main window
/// may not be the one the user is looking at.
enum AXWindowInspector {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPrompt() -> Bool {
        ensureAccessibilityAccess(promptForAccess: true)
    }

    static func snapshot(pid: pid_t, promptForAccess: Bool) -> AXWindowSnapshot {
        let trusted = promptForAccess
            ? ensureAccessibilityAccess(promptForAccess: true)
            : AXIsProcessTrusted()
        guard trusted else {
            return AXWindowSnapshot(trusted: false, title: nil, document: nil, windowSource: nil)
        }

        let appElement = AXUIElementCreateApplication(pid)
        let windows = candidateWindows(appElement: appElement)

        // Prefer the focused window so we never use another window's title when the user
        // has a different project window focused (e.g. feed-flow vs feed-flow-2).
        if let focused = windows.first(where: { $0.0 == "focused" }) {
            let title = copyStringAttribute(focused.1, attribute: kAXTitleAttribute as CFString)
            let document = copyStringAttribute(focused.1, attribute: kAXDocumentAttribute as CFString)
            return AXWindowSnapshot(
                trusted: true,
                title: title,
                document: document,
                windowSource: "focused"
            )
        }

        for (source, windowElement) in windows {
            let title = copyStringAttribute(windowElement, attribute: kAXTitleAttribute as CFString)
            let document = copyStringAttribute(windowElement, attribute: kAXDocumentAttribute as CFString)
            if title != nil || document != nil {
                return AXWindowSnapshot(
                    trusted: true,
                    title: title,
                    document: document,
                    windowSource: source
                )
            }
        }

        return AXWindowSnapshot(trusted: true, title: nil, document: nil, windowSource: nil)
    }

    private static func ensureAccessibilityAccess(promptForAccess: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: promptForAccess] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Collects candidate windows in priority order: focused, main, then all windows.
    /// Deduplicates by element identity so the same window isn't inspected twice.
    private static func candidateWindows(appElement: AXUIElement) -> [(String, AXUIElement)] {
        var result: [(String, AXUIElement)] = []
        var seen = Set<String>()

        if let focused = copyElementAttribute(appElement, attribute: kAXFocusedWindowAttribute as CFString) {
            appendWindow(source: "focused", element: focused, to: &result, seen: &seen)
        }

        if let main = copyElementAttribute(appElement, attribute: kAXMainWindowAttribute as CFString) {
            appendWindow(source: "main", element: main, to: &result, seen: &seen)
        }

        if let windows = copyElementArrayAttribute(appElement, attribute: kAXWindowsAttribute as CFString) {
            for (index, window) in windows.enumerated() {
                appendWindow(source: "windows[\(index)]", element: window, to: &result, seen: &seen)
            }
        }

        return result
    }

    private static func appendWindow(
        source: String,
        element: AXUIElement,
        to list: inout [(String, AXUIElement)],
        seen: inout Set<String>
    ) {
        let key = String(describing: element)
        guard seen.insert(key).inserted else { return }
        list.append((source, element))
    }

    private static func copyElementAttribute(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
    }

    private static func copyElementArrayAttribute(_ element: AXUIElement, attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        return value as? [AXUIElement]
    }

    private static func copyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        return value as? String
    }
}

import AppKit
import CoreGraphics
import SwiftyBeaver

/// Detects the active application and infers the target format
/// using bundle identifiers (Layer 1) and window titles (Layer 2).
struct ContextDetector: ContextDetecting {

    // MARK: - Layer 1: Bundle identifier → format

    private static let emailBundleIds: Set<String> = [
        "com.apple.mail",
        "com.microsoft.Outlook",
    ]

    /// Bundle identifiers of known browsers. When the frontmost app is a
    /// browser, we fall through to Layer 2 (window title matching).
    private static let browserBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",   // Arc
        "com.brave.Browser",
        "org.mozilla.firefox",
    ]

    // MARK: - Layer 2: Window title matching

    /// Email address pattern — strong signal that the tab is a mail client.
    private static let emailAddressPattern = try! NSRegularExpression(
        pattern: "\\S+@\\S+\\.\\S+", options: []
    )

    /// Substrings that indicate email context in a browser tab title.
    private static let emailWindowTitleSubstrings = [
        // Provider names
        "Gmail", "Outlook", "Yahoo Mail", "Proton Mail", "Zoho Mail",
        // Inbox terms (multilingual)
        "Inbox", "Posteingang", "Boîte de réception", "Bandeja de entrada",
        // Generic
        "Webmail", "Roundcube", "Horde",
    ]

    // MARK: - Detection

    func detectContext() -> FormatContext {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else {
            log.info("No frontmost app or bundle ID")
            return .general
        }

        log.info("Frontmost app: \(app.localizedName ?? "?") bundleId=\(bundleId)")

        // Layer 1: Direct app match (email only)
        if Self.emailBundleIds.contains(bundleId) {
            log.info("Layer 1 match → email")
            return .email
        }

        // Layer 2: Browser detected — check for webmail in window title
        if Self.browserBundleIds.contains(bundleId) {
            log.info("Layer 1: browser detected, checking window titles…")
            let titles = windowTitles(for: app.processIdentifier)
            if titles.isEmpty {
                log.warning("Layer 2: no window titles found (Screen Recording permission missing?)")
            }
            for title in titles {
                // Check for email address in title (strong signal)
                let range = NSRange(title.startIndex..., in: title)
                if Self.emailAddressPattern.firstMatch(in: title, range: range) != nil {
                    log.info("Layer 2 match: \"\(title)\" contains email address → email")
                    return .email
                }
                // Check for known email substrings
                for substring in Self.emailWindowTitleSubstrings {
                    if title.localizedCaseInsensitiveContains(substring) {
                        log.info("Layer 2 match: \"\(title)\" contains \"\(substring)\" → email")
                        return .email
                    }
                }
            }
            log.info("Layer 2: no email match in \(titles.count) title(s): \(titles)")
        } else {
            log.info("Layer 1: not an email app or known browser → general")
        }

        return .general
    }

    // MARK: - Window title retrieval

    /// Collect all non-empty window titles for the given process.
    /// Requires Screen Recording permission; returns empty array if unavailable.
    private func windowTitles(for pid: pid_t) -> [String] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var titles: [String] = []
        for window in windowList {
            guard let ownerPid = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPid == pid else {
                continue
            }
            let name = window[kCGWindowName as String] as? String ?? ""
            if !name.isEmpty {
                titles.append(name)
            }
        }
        return titles
    }

}
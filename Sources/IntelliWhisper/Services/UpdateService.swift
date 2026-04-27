import Foundation

/// Checks GitHub releases for a newer version and returns a `VersionCheckResult`.
struct UpdateService: Sendable {

    private static let apiURL = URL(string: "https://api.github.com/repos/AOTE-Holding/IntelliWhisper/releases/latest")!

    // MARK: - Public API

    /// Fetches the latest GitHub release and returns a `VersionCheckResult`.
    /// Returns nil if the check was rate-limited (silent mode), the API was
    /// unreachable, or the local version could not be read.
    func checkForUpdates(silent: Bool) async -> VersionCheckResult? {
        if silent, isRateLimited() { return nil }
        recordCheckTime()

        guard let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            log.warning("[UpdateService] Could not read CFBundleShortVersionString — not running from an app bundle")
            return nil
        }

        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 10
            return c
        }())

        var req = URLRequest(url: Self.apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard
            let (data, response) = try? await session.data(for: req),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let release = try? JSONDecoder().decode(GitHubRelease.self, from: data)
        else {
            log.warning("[UpdateService] GitHub API unreachable or returned an error")
            return nil
        }

        let remoteVersion = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        guard isNewer(remoteVersion, than: localVersion) else {
            log.info("[UpdateService] Already up to date (\(localVersion))")
            return .upToDate(currentVersion: localVersion, remoteVersion: remoteVersion)
        }

        log.info("[UpdateService] Update available: \(remoteVersion) (local: \(localVersion))")
        return .updateAvailable(UpdateInfo(
            version: remoteVersion,
            releaseNotes: release.body ?? ""
        ))
    }

    // MARK: - Private helpers

    private func isRateLimited() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: SettingsService.Keys.lastUpdateCheck) as? Date else {
            return false
        }
        return Date().timeIntervalSince(last) < 3600
    }

    private func recordCheckTime() {
        UserDefaults.standard.set(Date(), forKey: SettingsService.Keys.lastUpdateCheck)
    }

    /// Returns true if `remote` is a higher semver than `local`.
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for (rv, lv) in zip(r, l) {
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return r.count > l.count
    }
}

// MARK: - Supporting types

enum VersionCheckResult: Sendable {
    case upToDate(currentVersion: String, remoteVersion: String)
    case updateAvailable(UpdateInfo)
}

struct UpdateInfo: Sendable {
    let version: String
    let releaseNotes: String
}

// MARK: - GitHub API response model

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
    }
}

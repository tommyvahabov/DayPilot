import Foundation
import SwiftUI

@Observable
@MainActor
final class UpdateChecker {
    static let repo = "tommyvahabov/DayPilot"

    private(set) var latestVersion: String?
    private(set) var releaseURL: URL?
    private(set) var lastCheckedAt: Date?
    private(set) var isChecking = false

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    var isUpdateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return Self.compare(latest, currentVersion) == .orderedDescending
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false; lastCheckedAt = Date() }

        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tag = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            self.latestVersion = tag
            self.releaseURL = URL(string: release.html_url)
        } catch {
            // silent failure; offline / rate-limited
        }
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x > y { return .orderedDescending }
            if x < y { return .orderedAscending }
        }
        return .orderedSame
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
    }
}

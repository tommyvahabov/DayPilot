import Foundation
import SwiftUI
import AppKit

enum UpdateStatus: Equatable {
    case idle
    case downloading(progress: Double)
    case installing
    case failed(String)
}

@Observable
@MainActor
final class UpdateChecker {
    static let repo = "tommyvahabov/DayPilot"

    private(set) var latestVersion: String?
    private(set) var releaseURL: URL?
    private(set) var assetURL: URL?
    private(set) var lastCheckedAt: Date?
    private(set) var isChecking = false
    var status: UpdateStatus = .idle

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
            self.assetURL = release.assets
                .first(where: { $0.name.hasSuffix(".zip") })
                .flatMap { URL(string: $0.browser_download_url) }
        } catch {
            // silent
        }
    }

    func installUpdate() async {
        guard let assetURL = assetURL else {
            status = .failed("No download asset available")
            return
        }

        status = .downloading(progress: 0)

        do {
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DayPilotUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let zipURL = tmpDir.appendingPathComponent("DayPilot.zip")

            let (downloadedURL, _) = try await URLSession.shared.download(from: assetURL)
            try FileManager.default.moveItem(at: downloadedURL, to: zipURL)

            status = .installing

            try runDitto(["-xk", zipURL.path, tmpDir.path])

            let newAppURL = tmpDir.appendingPathComponent("DayPilot.app")
            guard FileManager.default.fileExists(atPath: newAppURL.path) else {
                throw NSError(domain: "Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: "DayPilot.app not found in archive"])
            }

            let currentURL = Bundle.main.bundleURL
            let backupURL = currentURL.deletingLastPathComponent()
                .appendingPathComponent(".DayPilot.app.old-\(UUID().uuidString)")

            if FileManager.default.fileExists(atPath: currentURL.path) {
                try FileManager.default.moveItem(at: currentURL, to: backupURL)
            }
            try FileManager.default.moveItem(at: newAppURL, to: currentURL)
            try? FileManager.default.removeItem(at: backupURL)

            let relaunchScript = """
            #!/bin/bash
            sleep 1
            open "\(currentURL.path)"
            """
            let scriptURL = tmpDir.appendingPathComponent("relaunch.sh")
            try relaunchScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scriptURL.path]
            try task.run()

            try? await Task.sleep(nanoseconds: 200_000_000)
            NSApp.terminate(nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func runDitto(_ args: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = args
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw NSError(domain: "Updater", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ditto failed (status \(task.terminationStatus))"])
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
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }
}

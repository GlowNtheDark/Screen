//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Nuke
import TVServices
import UIKit

#if DEBUG
import OSLog

private let topShelfDiagnosticsLogger = Logger(
    subsystem: "com.snowfin.tvos",
    category: "TopShelf"
)
#endif

@MainActor
enum ScreenTopShelfSnapshotWriter {

    private struct Candidate: Sendable {
        let deepLink: URL
        let id: String
        let imageURL: URL
        let progress: Double
        let title: String
    }

    private struct Snapshot: Codable, Sendable {
        let items: [Item]

        struct Item: Codable, Sendable {
            let deepLink: URL
            let id: String
            let imageFilename: String
            let progress: Double
            let title: String
        }
    }

    private nonisolated static let appGroupIdentifier = "group.com.snowfin.tvos"
    private nonisolated static let libraryDirectoryName = "Library"
    private nonisolated static let directoryName = "TopShelf"
    private nonisolated static let snapshotFilename = "continue-watching.json"
    private static var updateTask: Task<Void, Never>?

    static func clear() {
        updateTask?.cancel()
        updateTask = nil

        Task.detached(priority: .utility) {
            guard let appGroupURL = appGroupContainerURL() else {
                #if DEBUG
                topShelfDiagnosticsLogger.error(
                    "[SCREEN_TOP_SHELF] Clear failed: App Group container URL did not resolve"
                )
                #endif
                return
            }

            let directoryURL = topShelfDirectoryURL(in: appGroupURL)
            do {
                try FileManager.default.removeItem(at: directoryURL)
                #if DEBUG
                topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Existing snapshot directory cleared")
                #endif
            } catch {
                #if DEBUG
                let nsError = error as NSError
                if nsError.code == NSFileNoSuchFileError {
                    topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] No snapshot directory existed to clear")
                } else {
                    topShelfDiagnosticsLogger.error(
                        "[SCREEN_TOP_SHELF] Clear failed: \(safeErrorDescription(error), privacy: .public)"
                    )
                }
                #endif
            }
            TVTopShelfContentProvider.topShelfContentDidChange()
            #if DEBUG
            topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Top Shelf content change notification sent after clear")
            #endif
        }
    }

    static func update(items: [BaseItemDto]) {
        updateTask?.cancel()

        #if DEBUG
        topShelfDiagnosticsLogger.debug(
            "[SCREEN_TOP_SHELF] Snapshot update requested items=\(items.count, privacy: .public)"
        )
        #endif

        guard let session = Container.shared.currentUserSession() else {
            #if DEBUG
            topShelfDiagnosticsLogger.error(
                "[SCREEN_TOP_SHELF] Snapshot update has no active user session; clearing snapshot"
            )
            #endif
            clear()
            return
        }

        // A presentation-only update does not invalidate a Continue query, so
        // that query may finish with a DTO carrying older progress. Resolve the
        // mutable projection value from the session state before writing it.
        let currentItems = items.prefix(12).map { item in
            session.itemStateStore.state(for: item)?.applying(to: item) ?? item
        }

        var missingIDCount = 0
        var missingArtworkCount = 0
        var invalidDeepLinkCount = 0
        let candidates = currentItems.compactMap { item -> Candidate? in
            guard let id = item.id else {
                missingIDCount += 1
                return nil
            }

            guard let imageURL = landscapeImageURL(for: item) else {
                missingArtworkCount += 1
                return nil
            }

            guard let deepLink = URL(string: "swiftfin://\(session.server.id)/\(session.user.id)/item/\(id)") else {
                invalidDeepLinkCount += 1
                return nil
            }

            let position = Double(item.userData?.playbackPositionTicks ?? 0)
            let duration = Double(item.runTimeTicks ?? 0)
            let progress = duration > 0 ? min(max(position / duration, 0), 1) : 0

            return Candidate(
                deepLink: deepLink,
                id: id,
                imageURL: imageURL,
                progress: progress,
                title: topShelfTitle(for: item)
            )
        }

        #if DEBUG
        topShelfDiagnosticsLogger.debug(
            "[SCREEN_TOP_SHELF] Candidate preparation complete candidates=\(candidates.count, privacy: .public) missingID=\(missingIDCount, privacy: .public) missingArtworkURL=\(missingArtworkCount, privacy: .public) invalidDeepLink=\(invalidDeepLinkCount, privacy: .public)"
        )
        #endif

        updateTask = Task.detached(priority: .utility) {
            await writeSnapshot(for: candidates)
        }
    }

    private static func topShelfTitle(for item: BaseItemDto) -> String {
        guard item.type == .episode else { return item.displayTitle }

        let seriesName = item.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let episodeTitle = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let episodeNumber: String? = {
            switch (item.parentIndexNumber, item.indexNumber) {
            case let (season?, episode?):
                "S\(season):E\(episode)"
            case let (nil, episode?):
                "E\(episode)"
            case let (season?, nil):
                "S\(season)"
            case (nil, nil):
                nil
            }
        }()
        let details = [episodeNumber, episodeTitle]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        // Sectioned Top Shelf items have one native title, with no subtitle API.
        // tvOS controls how the line break is displayed and truncated.
        let title = [seriesName, details]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return title.isEmpty ? item.displayTitle : title
    }

    private static func landscapeImageURL(for item: BaseItemDto) -> URL? {
        var environment = BaseItemDto.Environment.default
        environment.viewContext.insert(.isThumb)

        return item.imageSources(
            for: .landscape,
            size: .custom(width: 1816),
            environment: environment
        )
        .first?
        .url
    }

    private nonisolated static func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private nonisolated static func topShelfDirectoryURL(in appGroupURL: URL) -> URL {
        appGroupURL
            .appendingPathComponent(libraryDirectoryName, isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private nonisolated static func writeSnapshot(for candidates: [Candidate]) async {
        #if DEBUG
        topShelfDiagnosticsLogger.debug(
            "[SCREEN_TOP_SHELF] Snapshot processing started candidates=\(candidates.count, privacy: .public)"
        )
        #endif

        guard !Task.isCancelled else {
            #if DEBUG
            topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Snapshot processing cancelled before filesystem work")
            #endif
            return
        }

        guard let appGroupURL = appGroupContainerURL() else {
            #if DEBUG
            topShelfDiagnosticsLogger.error(
                "[SCREEN_TOP_SHELF] Snapshot processing failed: App Group container URL did not resolve"
            )
            #endif
            return
        }

        #if DEBUG
        topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] App Group container URL resolved")
        #endif
        let directoryURL = topShelfDirectoryURL(in: appGroupURL)
        var stage = "directory creation"
        var artworkPreparedCount = 0
        var artworkSkippedCount = 0

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            #if DEBUG
            topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Snapshot directory creation succeeded")
            #endif

            var snapshotItems: [Snapshot.Item] = []

            for candidate in candidates {
                guard !Task.isCancelled else {
                    #if DEBUG
                    topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Snapshot processing cancelled during artwork preparation")
                    #endif
                    return
                }

                let request = ImageRequest(url: candidate.imageURL)
                let image: UIImage?
                do {
                    image = try await ImagePipeline.Screen.posters.image(for: request)
                } catch {
                    artworkSkippedCount += 1
                    #if DEBUG
                    topShelfDiagnosticsLogger.error(
                        "[SCREEN_TOP_SHELF] Artwork request failed: \(safeErrorDescription(error), privacy: .public)"
                    )
                    #endif
                    continue
                }

                guard let image else {
                    artworkSkippedCount += 1
                    #if DEBUG
                    topShelfDiagnosticsLogger.error("[SCREEN_TOP_SHELF] Artwork request returned no image")
                    #endif
                    continue
                }

                guard let data = image.jpegData(compressionQuality: 0.9) else {
                    artworkSkippedCount += 1
                    #if DEBUG
                    topShelfDiagnosticsLogger.error("[SCREEN_TOP_SHELF] Artwork JPEG preparation returned no data")
                    #endif
                    continue
                }

                let imageFilename = "\(candidate.id).jpg"
                stage = "artwork file write"
                try data.write(
                    to: directoryURL.appendingPathComponent(imageFilename),
                    options: .atomic
                )
                artworkPreparedCount += 1
                #if DEBUG
                topShelfDiagnosticsLogger.debug(
                    "[SCREEN_TOP_SHELF] Artwork file write succeeded prepared=\(artworkPreparedCount, privacy: .public)"
                )
                #endif

                snapshotItems.append(
                    .init(
                        deepLink: candidate.deepLink,
                        id: candidate.id,
                        imageFilename: imageFilename,
                        progress: candidate.progress,
                        title: candidate.title
                    )
                )
            }

            guard !Task.isCancelled else {
                #if DEBUG
                topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Snapshot processing cancelled before JSON write")
                #endif
                return
            }

            stage = "JSON encoding"
            let snapshot = Snapshot(items: snapshotItems)
            let data = try JSONEncoder().encode(snapshot)
            #if DEBUG
            topShelfDiagnosticsLogger.debug(
                "[SCREEN_TOP_SHELF] JSON encoding succeeded items=\(snapshotItems.count, privacy: .public) artworkPrepared=\(artworkPreparedCount, privacy: .public) artworkSkipped=\(artworkSkippedCount, privacy: .public)"
            )
            #endif

            stage = "snapshot file write"
            try data.write(
                to: directoryURL.appendingPathComponent(snapshotFilename),
                options: .atomic
            )
            #if DEBUG
            topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Snapshot file write succeeded")
            #endif

            stage = "stale file cleanup"
            let retainedFilenames = Set(snapshotItems.map(\.imageFilename) + [snapshotFilename])
            let existingURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
            for url in existingURLs where !retainedFilenames.contains(url.lastPathComponent) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    #if DEBUG
                    topShelfDiagnosticsLogger.error(
                        "[SCREEN_TOP_SHELF] Stale file cleanup failed: \(safeErrorDescription(error), privacy: .public)"
                    )
                    #endif
                }
            }

            TVTopShelfContentProvider.topShelfContentDidChange()
            #if DEBUG
            topShelfDiagnosticsLogger.debug("[SCREEN_TOP_SHELF] Top Shelf content change notification sent")
            #endif
        } catch {
            #if DEBUG
            topShelfDiagnosticsLogger.error(
                "[SCREEN_TOP_SHELF] Snapshot processing failed at \(stage, privacy: .public): \(safeErrorDescription(error), privacy: .public)"
            )
            #endif
            return
        }
    }

    #if DEBUG
    private nonisolated static func safeErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        let redactedDescription = nsError.localizedDescription
            .replacingOccurrences(
                of: #"(?i)(?:https?|swiftfin)://[^\s\"']+"#,
                with: "<redacted-url>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}\b|\b[0-9a-fA-F]{24,}\b"#,
                with: "<redacted-id>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(api[_-]?key|access[_-]?token|token|authorization)=([^&\s]+)"#,
                with: "$1=<redacted>",
                options: .regularExpression
            )
        return "domain=\(nsError.domain) code=\(nsError.code) description=\(redactedDescription)"
    }
    #endif
}

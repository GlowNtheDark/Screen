//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import Logging
import Nuke
import Pulse
import UIKit

extension ImagePipeline {

    enum Screen {}

    nonisolated static func cacheKey(for url: URL) -> String? {
        guard var components = url.components else { return nil }

        var maxWidthValue: String?

        // TODO: maxHeight
        // TODO: cache reset

        if let maxWidth = components.queryItems?.first(where: { $0.name == "maxWidth" }) {
            maxWidthValue = maxWidth.value
            components.queryItems = components.queryItems?.filter { $0.name != "maxWidth" }
        }

        guard let newURL = components.url, let urlSHA = newURL.pathAndQuery?.sha1 else { return nil }

        if let maxWidthValue {
            return urlSHA + "-\(maxWidthValue)"
        } else {
            return urlSHA
        }
    }

    func loadFirstImage(from requests: some Collection<ImageSource>) async -> UIImage? {
        guard let url = requests.first?.url else { return nil }

        do {
            return try await image(for: url)
        } catch {
            let requests = requests.dropFirst()
            return await loadFirstImage(from: requests)
        }
    }

    func removeItem(for url: URL) {
        let request = ImageRequest(url: url)
        cache.removeCachedImage(for: request)
        cache.removeCachedData(for: request)

        guard let dataCacheKey = Self.cacheKey(for: url) else { return }
        configuration.dataCache?.removeData(for: dataCacheKey)
    }
}

extension ImagePipeline.Screen {

    /// The default `ImagePipeline` to use for images that are typically posters
    /// or server user images that should be presentable with an active connection.
    static let posters: ImagePipeline = ImagePipeline(delegate: ScreenImagePipelineDelegate(logMetrics: true)) { config in
        config.dataCache = DataCache.Screen.posters
        config.isUsingPrepareForDisplay = true

        let dataLoader = DataLoader(
            configuration: .screen
        )
        dataLoader.delegate = URLSessionProxyDelegate(
            logger: NetworkLogger.screen(),
            delegate: nil
        )
        config.dataLoader = dataLoader
    }

    /// The `ImagePipeline` used for images that should have longer lifetimes and usable
    /// without a connection, likes local user profile images and server splashscreens.
    static let local: ImagePipeline = ImagePipeline(delegate: ScreenImagePipelineDelegate()) { config in
        config.dataCache = DataCache.Screen.local

        let dataLoader = DataLoader(
            configuration: .screen
        )
        dataLoader.delegate = URLSessionProxyDelegate(
            logger: NetworkLogger.screen(),
            delegate: nil
        )
        config.dataLoader = dataLoader
    }

    /// An `ImagePipeline` for images to prevent more important images from losing their cache.
    static let other: ImagePipeline = ImagePipeline(configuration: .withURLCache)
}

final class ScreenImagePipelineDelegate: ImagePipeline.Delegate, @unchecked Sendable {

    private struct Metrics {
        var cancellations = 0
        var completions = 0
        var dataLoads = 0
        var diskHits = 0
        var failures = 0
        var memoryHits = 0
        var uncachedResponses = 0
    }

    private let lock = NSLock()
    private let logMetrics: Bool
    private let logger = Logger.screen()
    private var lastReportedCompletions = 0
    private var metrics = Metrics()

    init(logMetrics: Bool = false) {
        self.logMetrics = logMetrics
    }

    private func record(_ update: (inout Metrics) -> Void) {
        guard logMetrics else { return }

        let snapshot: Metrics?

        lock.lock()
        update(&metrics)
        if metrics.completions > lastReportedCompletions, metrics.completions.isMultiple(of: 25) {
            lastReportedCompletions = metrics.completions
            snapshot = metrics
        } else {
            snapshot = nil
        }
        lock.unlock()

        guard let snapshot else { return }

        logger.debug(
            """
            Poster image pipeline metrics: completed=\(snapshot.completions), memoryHits=\(snapshot.memoryHits), \
            diskHits=\(snapshot.diskHits), dataLoads=\(snapshot.dataLoads), \
            uncachedResponses=\(snapshot.uncachedResponses), cancelled=\(snapshot.cancellations), \
            failures=\(snapshot.failures)
            """
        )
    }

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        guard let url = request.url else { return nil }
        return ImagePipeline.cacheKey(for: url)
    }

    @ImagePipelineActor
    func willLoadData(
        for request: ImageRequest,
        urlRequest: URLRequest,
        pipeline: ImagePipeline
    ) async throws -> URLRequest {
        record { $0.dataLoads += 1 }
        return urlRequest
    }

    func imageTask(
        _ task: ImageTask,
        didReceiveEvent event: ImageTask.Event,
        pipeline: ImagePipeline
    ) {
        guard case let .finished(result) = event else { return }

        switch result {
        case let .success(response):
            record { metrics in
                metrics.completions += 1

                switch response.cacheType {
                case .memory:
                    metrics.memoryHits += 1
                case .disk:
                    metrics.diskHits += 1
                case nil:
                    metrics.uncachedResponses += 1
                }
            }
        case .failure(.cancelled):
            record { $0.cancellations += 1 }
        case .failure:
            record { $0.failures += 1 }
        }
    }
}

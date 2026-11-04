//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import VLCUI

// TODO: proper error catching
// TODO: be a UserSessionService?

typealias MediaPlayerManagerPublisher = LegacyEventPublisher<MediaPlayerManager?>

#if DEBUG
enum EpisodePlaybackDiagnostics {

    private static let logger = Logger(label: "Screen.EpisodePlayback")

    static func logEpisodesBack(_ diagnosticID: String?, event: String) {
        guard let diagnosticID else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime
        logger.debug("[SCREEN_EPISODES_BACK] t=\(timestamp) trace=\(diagnosticID) \(event)")
    }

    static func log(_ diagnosticID: String?, event: String) {
        guard let diagnosticID else { return }
        logger.debug("[SCREEN_EPISODE_PLAYBACK] trace=\(diagnosticID) \(event)")
    }
}
#endif

extension Scope {
    static let session = Cached()
}

extension Container {

    var mediaPlayerManagerPublisher: Factory<MediaPlayerManagerPublisher> {
        self { MediaPlayerManagerPublisher() }
            .singleton
    }

    var mediaPlayerManager: Factory<MediaPlayerManager> {
        self { @MainActor in
            .init(
                playbackItem: .init(
                    baseItem: .init(),
                    mediaSource: .init(),
                    playSessionID: "",
                    url: URL(string: "/")!,
                    deviceProfile: .init()
                )
            )
        }
        .scope(.session)
    }
}

import StatefulMacros

@MainActor
@Stateful
final class MediaPlayerManager: ViewModel {

    @CasePathable
    enum Action {
        case ended
        case error
        case playNewItem(provider: MediaPlayerItemProvider)
        case playNewItemCompletingCurrent(provider: MediaPlayerItemProvider)
        case setBitrate(bitrate: PlaybackBitrate)
        case setPlaybackRequestStatus(status: PlaybackRequestStatus)
        case setRate(rate: Float)
        case setTrack(type: MediaStreamType, from: Int?, to: Int? = nil)
        case start
        case stop
        case togglePlayPause

        var transition: Transition {
            switch self {
            case .error:
                .to(.error)
                    .invalid(.stopped)
            case .playNewItem, .playNewItemCompletingCurrent, .start:
                .to(.loadingItem, then: .playback)
                    .invalid(.stopped)
            case .stop:
                .to(.stopped)
            default:
                .none
                    .invalid(.stopped)
            }
        }
    }

    enum State {
        case error
        case initial
        case loadingItem
        case playback
        case stopped
    }

    /// A status indicating the player's request for media playback.
    enum PlaybackRequestStatus {

        /// The player requests media playback
        case playing

        /// The player is paused
        case paused
    }

    @Published
    var playbackItem: MediaPlayerItem? = nil {
        didSet {
            if let playbackItem {
                self.item = playbackItem.baseItem
                seconds = playbackItem.baseItem.startSeconds ?? .zero
                playbackItem.manager = self
                setSupplements()
                screenSegmentCoordinator.prepare(for: playbackItem)

                logger.info(
                    "Playing new item",
                    metadata: [
                        "isTranscoding": .stringConvertible(playbackItem.mediaSource.transcodingURL != nil),
                    ]
                )

                Task { _ = await playbackItem.previewImageProvider?.image(for: seconds) }
            } else {
                screenSegmentCoordinator.prepare(for: nil)
            }
        }
    }

    @Published
    private(set) var item: BaseItemDto
    @Published
    private(set) var playbackRequestStatus: PlaybackRequestStatus = .playing
    @Published
    var rate: Float = Defaults[.VideoPlayer.Playback.playbackRate] {
        didSet {
            Defaults[.VideoPlayer.Playback.playbackRate] = rate
        }
    }

    @Published
    var queue: AnyMediaPlayerQueue? = nil

    @Published
    var supplements: [any MediaPlayerSupplement] = []

    lazy var screenSegmentCoordinator = ScreenPlaybackSegmentCoordinator(manager: self)

    /// Snapshot the real outgoing position before stopping the proxy can reset it.
    private(set) var previousItemStopSeconds: Duration?

    let episodePlaybackDiagnosticID: String?

    #if DEBUG
    private var didLogEpisodePlaybackStart = false
    #endif

    // TODO: replace with graph dependency package
    private func setSupplements() {
        var newSupplements = Defaults[.VideoPlayer.supplements].compactMap { kind -> (any MediaPlayerSupplement)? in
            switch kind {
            case .info:
                return MediaInfoSupplement(item: item)
            case .chapters:
                guard let chapters = item.fullChapterInfo, chapters.isNotEmpty else { return nil }
                return MediaChaptersSupplement(chapters: chapters)
            case .queue:
                return queue
            case .people:
                guard let people = item.people?.filter({ $0.type?.isSupported == true }), people.isNotEmpty else { return nil }
                return MediaPeopleSupplement(people: people)
            case .playbackInformation:
                guard let itemID = item.id else { return nil }
                return PlaybackInformationSupplement(itemID: itemID)
            }
        }

        if item.isLiveStream, Defaults[.Experimental.videoPlayerEPG] {
            newSupplements.append(EPGSupplement())
        }

        self.supplements = newSupplements
    }

    /// The current seconds media playback is set to.
    let secondsBox: PublishedBox<Duration> = .init(initialValue: .zero)

    var seconds: Duration {
        get { secondsBox.value }
        set { secondsBox.value = newValue }
    }

    var playbackBitrate: PlaybackBitrate {
        playbackItem?.requestedBitrate ?? Defaults[.VideoPlayer.Playback.appMaximumBitrate]
    }

    /// Holds a weak reference to the current media player proxy.
    weak var proxy: (any MediaPlayerProxy)? {
        didSet {
            if var proxy {
                proxy.manager = self
            }
        }
    }

    private var initialMediaPlayerItemProvider: MediaPlayerItemProvider?

    // MARK: init

//    static let empty: MediaPlayerManager = .init()

//    override private init() {
//        self.item = .init()
//        self.state = .stopped
//        super.init()
//    }

    init(
        provider: MediaPlayerItemProvider,
        queue: (any MediaPlayerQueue)? = nil
    ) {
        RuntimeDiagnostics.playback.notice("event=player.created source=provider")
        self.item = provider.item
        self.queue = queue.map { AnyMediaPlayerQueue($0) }
        self.episodePlaybackDiagnosticID = (queue as? EpisodeMediaPlayerQueue)?.playbackDiagnosticID
        self.state = .loadingItem
        self.initialMediaPlayerItemProvider = provider
        super.init()

        self.queue?.manager = self
    }

    init(
        playbackItem: MediaPlayerItem,
        queue: (any MediaPlayerQueue)? = nil
    ) {
        RuntimeDiagnostics.playback.notice("event=player.created source=playback_item")
        self.item = playbackItem.baseItem
        self.queue = queue.map { AnyMediaPlayerQueue($0) }
        self.episodePlaybackDiagnosticID = (queue as? EpisodeMediaPlayerQueue)?.playbackDiagnosticID
        self.state = .playback
        super.init()

        self.queue?.manager = self
        self.playbackItem = playbackItem
    }

    @Function(\Action.Cases.ended)
    private func _ended() async throws {
        // TODO: change to observe given seconds against runtime
        //       instead of sent action?

        // Ended should represent natural ending of playback, which
        // is verifiable by given seconds being near item runtime.
        // VLC proxy will send ended early.
        guard let runtime = item.runtime else {
            await self.stop()
            return
        }
        let isNearEnd = (runtime - seconds) <= .seconds(1)

        guard isNearEnd else {
            // If not near end, ignore.
            return
        }

        if let nextItem = queue?.nextItem, try authenticatedUser.data.configuration?.enableNextEpisodeAutoPlay == true {
            await self.playNewItem(provider: nextItem)
        } else {
            await self.stop()
        }
    }

    @Function(\Action.Cases.error)
    private func onError(_ error: Error) async throws {
        #if DEBUG
        Self.logEpisodePlayback(
            episodePlaybackDiagnosticID,
            event: "manager-error"
        )
        #endif

        RuntimeDiagnostics.playback.error("event=player.failed")
        logger.error("Error while playing media")

        proxy?.stop()
        Container.shared.mediaPlayerManagerPublisher().send(nil)
        Container.shared.mediaPlayerManager.reset()
    }

    @Function(\Action.Cases.playNewItem)
    private func _playNewItem(_ provider: MediaPlayerItemProvider) async throws {
        try await replacePlaybackItem(with: provider)
    }

    @Function(\Action.Cases.playNewItemCompletingCurrent)
    private func _playNewItemCompletingCurrent(_ provider: MediaPlayerItemProvider) async throws {
        guard let itemID = playbackItem?.baseItem.id else { return }
        let userSession = try requireUserSession()
        let revision = DispatchTime.now().uptimeNanoseconds
        let request = try Paths.markPlayedItem(itemID: itemID, userID: userSession.user.id)
        let response = try await userSession.client.send(request)
        Notifications[.itemUserDataDidChange].post(ItemUpdate(
            userSessionID: userSession.id,
            itemID: itemID,
            revision: revision,
            change: .userData(response.value)
        ))
        try await replacePlaybackItem(with: provider)
        RuntimeDiagnostics.playback.notice("event=play_next.transition_completed")
    }

    private func replacePlaybackItem(
        with provider: MediaPlayerItemProvider
    ) async throws {
        previousItemStopSeconds = seconds
        defer { previousItemStopSeconds = nil }
        item = provider.item
        setSupplements()
        proxy?.stop()
        let newPlaybackItem = try await provider()

        playbackItem = newPlaybackItem
    }

    @Function(\Action.Cases.setBitrate)
    private func _setBitrate(_ requestedBitrate: PlaybackBitrate) async throws {
        guard let currentItem = playbackItem else { return }

        try await updateMediaPlayerItem(
            currentItem: currentItem,
            requestedBitrate: requestedBitrate
        )
    }

    @Function(\Action.Cases.setPlaybackRequestStatus)
    private func set(_ status: PlaybackRequestStatus) {
        if self.playbackRequestStatus != status {
            RuntimeDiagnostics.playback.notice(
                "event=player.state_transition status=\(status == .playing ? "playing" : "paused", privacy: .public)"
            )
            self.playbackRequestStatus = status

            switch status {
            case .paused:
                proxy?.pause()
            case .playing:
                proxy?.play()
            }
        }
    }

    @Function(\Action.Cases.setRate)
    private func set(_ rate: Float) {
        if self.rate != rate {
            self.rate = rate
        }
    }

    @Function(\Action.Cases.setTrack)
    private func _setTrack(_ type: MediaStreamType, _ oldIndex: Int?, _ newIndex: Int?) async throws {
        guard let playbackItem else {
            logger.warning("MediaPlayerManager.SetTrack call with an invalid playbackItem")
            return
        }

        switch type {
        case .audio:
            guard playbackItem.audioStreams.contains(where: { $0.index == oldIndex }) else {
                logger.warning("MediaPlayerManager.SetTrack call with an invalid audio track index")
                return
            }

            if playbackItem.isRebuildRequired(type: .audio, from: oldIndex, to: newIndex) {
                try await updateMediaPlayerItem(
                    currentItem: playbackItem,
                    audioStreamIndex: newIndex
                )
            } else {
                playbackItem.switchTrack(type: .audio, index: newIndex)
            }
        case .subtitle:
            guard newIndex == -1 || playbackItem.subtitleStreams.contains(where: { $0.index == newIndex }) else {
                logger.warning("MediaPlayerManager.SetTrack call with an invalid subtitle track index")
                return
            }

            if playbackItem.isRebuildRequired(type: .subtitle, from: oldIndex, to: newIndex) {
                try await updateMediaPlayerItem(
                    currentItem: playbackItem,
                    subtitleStreamIndex: newIndex
                )
            } else {
                playbackItem.switchTrack(type: .subtitle, index: newIndex)
            }
        default:
            logger.warning("MediaPlayerManager.SetTrack called with unsupported type: \(String(describing: type))")
        }
    }

    @Function(\Action.Cases.start)
    private func _start() async throws {
        RuntimeDiagnostics.playback.notice("event=player.started")
        guard let initialMediaPlayerItemProvider else {
            await self.stop()
            return
        }
        self.initialMediaPlayerItemProvider = nil
        playbackItem = try await initialMediaPlayerItemProvider()

        #if DEBUG
        Self.logEpisodePlayback(
            episodePlaybackDiagnosticID,
            event: "media-item-resolved"
        )
        #endif
    }

    // TODO: remove playback item?
    //       - check that observers would respond correctly to stopping
    @Function(\Action.Cases.stop)
    private func _stop() async throws {
        RuntimeDiagnostics.playback.notice("event=player.stopped")
        #if DEBUG
        Self.logEpisodePlayback(
            episodePlaybackDiagnosticID,
            event: "manager-stop-began"
        )
        #endif

        await self.cancel()

        screenSegmentCoordinator.reset()
        proxy?.stop()
        RuntimeDiagnostics.playback.notice("event=player.dismissed reason=stopped")
        Container.shared.mediaPlayerManagerPublisher().send(nil)
        Container.shared.mediaPlayerManager.reset()

        #if DEBUG
        Self.logEpisodePlayback(episodePlaybackDiagnosticID, event: "manager-stop-finished")
        #endif
    }

    @Function(\Action.Cases.togglePlayPause)
    private func _togglePlayPause() {
        switch playbackRequestStatus {
        case .playing:
            RuntimeDiagnostics.playback.notice("event=player.paused source=user_action")
            setPlaybackRequestStatus(status: .paused)
        case .paused:
            RuntimeDiagnostics.playback.notice("event=player.resumed source=user_action")
            setPlaybackRequestStatus(status: .playing)
        }
    }

    #if DEBUG
    func logEpisodePlaybackStarted(backend: String) {
        guard let episodePlaybackDiagnosticID, !didLogEpisodePlaybackStart else { return }
        didLogEpisodePlaybackStart = true
        Self.logEpisodePlayback(
            episodePlaybackDiagnosticID,
            event: "backend-playing backend=\(backend)"
        )
    }

    static func logEpisodePlayback(_ diagnosticID: String?, event: String) {
        EpisodePlaybackDiagnostics.log(diagnosticID, event: event)
    }
    #endif

    /// Rebuilds the playback item with new stream indexes / bitrate.
    /// Stops the current proxy, requests new playback info from the server, and starts playback with the new configuration.
    ///
    /// Rebuilds the current item
    private func updateMediaPlayerItem(
        currentItem: MediaPlayerItem,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        requestedBitrate: PlaybackBitrate? = nil
    ) async throws {

        // Capture the current playback position before stopping
        let currentSeconds = self.seconds

        logger.info(
            "Rebuilding Media Player Item",
            metadata: [
                "audioIndex": "\(audioStreamIndex ?? -1)",
                "subtitleIndex": "\(subtitleStreamIndex ?? -1)",
                "currentSeconds": "\(currentSeconds)",
            ]
        )

        proxy?.stop()

        let newItem = try await MediaPlayerItem.build(
            for: currentItem.baseItem,
            mediaSource: currentItem.mediaSource,
            audioStreamIndex: audioStreamIndex ?? currentItem.selectedAudioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex ?? currentItem.selectedSubtitleStreamIndex,
            requestedBitrate: requestedBitrate ?? currentItem.requestedBitrate,
            modifyItem: { item in
                if item.userData == nil {
                    item.userData = UserItemDataDto(key: "")
                }
                item.userData?.playbackPositionTicks = currentSeconds.ticks
            }
        )

        logger.info(
            "Built new playback item",
            metadata: [
                "isTranscoding": "\(newItem.mediaSource.transcodingURL != nil)",
            ]
        )

        self.playbackItem = newItem
        self.seconds = currentSeconds
    }

    nonisolated static func getMaxBitrate(
        for requestedBitrate: PlaybackBitrate,
        testSize: PlaybackBitrateTestSize = Defaults[.VideoPlayer.appMaximumBitrateTest]
    ) async throws -> Int {

        guard requestedBitrate == .auto else { return requestedBitrate.rawValue }

        guard let userSession = Container.shared.currentUserSession() else {
            throw UserSessionError.missingCurrentSession
        }

        let testStartTime = Date()
        let _ = try await userSession.client.send(Paths.getBitrateTestBytes(size: testSize.rawValue))
        let testDuration = Date().timeIntervalSince(testStartTime)
        let testSizeBits = Double(testSize.rawValue * 8)
        let testBitrate = testSizeBits / testDuration

        return clamp(
            Int(testBitrate),
            min: PlaybackBitrate.kbps420.rawValue,
            max: Int(Int32.max)
        )
    }
}

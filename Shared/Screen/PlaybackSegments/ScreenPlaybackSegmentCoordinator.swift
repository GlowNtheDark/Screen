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

@MainActor
final class ScreenPlaybackSegmentCoordinator: ObservableObject {

    struct Presentation {
        enum Kind: Equatable {
            case intro
            case nextEpisode
            case countdown
        }

        let kind: Kind
        let item: BaseItemDto?
        let remainingSeconds: Int?
        let countdownDurationSeconds: Int?
        let countdownProgress: Double?
    }

    @Published
    private(set) var presentation: Presentation?

    @Published
    private(set) var isOverlayPresented = false

    var currentItem: BaseItemDto? {
        manager?.item
    }

    var isNextEpisodeTransitionPresented: Bool {
        guard let presentation else { return false }

        switch presentation.kind {
        case .nextEpisode, .countdown:
            return true
        case .intro:
            return false
        }
    }

    private weak var manager: MediaPlayerManager?
    private var segments: [ScreenPlaybackSegment] = []
    private var handledSegmentIDs: Set<String> = []
    private var previousSeconds: Duration = .zero
    private var playbackTimeUpdateGeneration = 0
    private var itemStartSeconds: Duration = .zero
    private var currentItemID: String?
    private var activeSegment: ScreenPlaybackSegment?
    private var pendingCreditsSegment: ScreenPlaybackSegment?
    private var cancelledCountdownSegmentIDs: Set<String> = []
    private var nextItemProvider: MediaPlayerItemProvider?
    private var segmentTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(manager: MediaPlayerManager) {
        self.manager = manager
        previousSeconds = manager.seconds

        manager.secondsBox.$value
            .removeDuplicates()
            .sink { [weak self] seconds in
                self?.playbackTimeDidChange(to: seconds)
            }
            .store(in: &cancellables)

        manager.queue?.nextItemPublisher
            .sink { [weak self] provider in
                self?.nextItemDidResolve(provider)
            }
            .store(in: &cancellables)
    }

    deinit {
        segmentTask?.cancel()
        countdownTask?.cancel()
    }

    func prepare(for playbackItem: MediaPlayerItem?) {
        reset()

        currentItemID = playbackItem?.baseItem.id
        itemStartSeconds = manager?.seconds ?? playbackItem?.baseItem.startSeconds ?? .zero
        previousSeconds = itemStartSeconds
        nextItemProvider = manager?.queue?.nextItem

        guard let itemID = currentItemID,
              playbackItem?.baseItem.isLiveStream == false
        else { return }

        segmentTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard let userSession = Container.shared.currentUserSession() else {
                    return
                }

                let request = Paths.getItemSegments(
                    itemID: itemID,
                    includeSegmentTypes: [.intro, .outro]
                )
                let response = try await userSession.client.send(request)
                guard !Task.isCancelled, self.currentItemID == itemID else { return }

                self.segments = (response.value.items ?? [])
                    .compactMap(ScreenPlaybackSegment.init)
                    .sorted { $0.start < $1.start }

                self.log(
                    "Retrieved \(self.segments.count) playback segments",
                    itemID: itemID
                )

                if let current = self.manager?.seconds {
                    let updateGeneration = self.playbackTimeUpdateGeneration
                    self.evaluateCrossings(from: self.itemStartSeconds, to: current)
                    if self.playbackTimeUpdateGeneration == updateGeneration {
                        self.previousSeconds = current
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.log("Segment retrieval failed: \(error.localizedDescription)", itemID: itemID)
            }
        }
    }

    func reset() {
        segmentTask?.cancel()
        countdownTask?.cancel()
        dismissOverlay()
        segments = []
        handledSegmentIDs = []
        cancelledCountdownSegmentIDs = []
        activeSegment = nil
        pendingCreditsSegment = nil
        currentItemID = nil
        nextItemProvider = nil
        countdownTask = nil
        segmentTask = nil
    }

    func skipIntro() {
        guard let segment = activeSegment, segment.type == .intro else { return }
        handledSegmentIDs.insert(segment.id)
        dismissOverlay()
        activeSegment = nil
        seek(to: segment.end)
        log("Intro skipped", segment: segment)
    }

    /// Consumes Back for the currently visible intro or credits/Play Next state.
    /// A running countdown is cancelled first; a later Back dismisses the resulting
    /// Play Next choice before the player HUD or route can receive it.
    func handleMenuBack() -> Bool {
        guard let presentation else { return false }

        switch presentation.kind {
        case .intro:
            let segment = activeSegment
            activeSegment = nil
            dismissOverlay()
            if let segment {
                log("Intro prompt dismissed with Back", segment: segment)
            }

        case .countdown:
            if cancelCountdown() {
                return true
            }
            dismissCreditsPresentation()

        case .nextEpisode:
            dismissCreditsPresentation()
        }

        return true
    }

    func playNextEpisode() {
        guard let manager,
              let provider = nextItemProvider,
              let segment = activeSegment ?? pendingCreditsSegment
        else { return }

        countdownTask?.cancel()
        countdownTask = nil
        handledSegmentIDs.insert(segment.id)
        dismissOverlay()
        activeSegment = nil
        pendingCreditsSegment = nil
        log("Starting resolved next episode \(provider.item.id ?? "Unknown")")
        manager.playNewItemCompletingCurrent(provider: provider)
    }

    func playContinueWatching(_ item: BaseItemDto) {
        guard let manager,
              let provider = item.getPlaybackItemProvider(userSession: nil)
        else { return }

        countdownTask?.cancel()
        countdownTask = nil
        dismissOverlay()
        activeSegment = nil
        pendingCreditsSegment = nil
        log("Starting Continue Watching item \(item.id ?? "Unknown")")
        manager.playNewItem(provider: provider)
    }

    func keepWatching() {
        guard let segment = activeSegment ?? pendingCreditsSegment else { return }
        countdownTask?.cancel()
        countdownTask = nil
        handledSegmentIDs.insert(segment.id)
        dismissOverlay()
        activeSegment = nil
        pendingCreditsSegment = nil
        log("Credits autoplay cancelled with Keep Watching", segment: segment)
    }

    @discardableResult
    func cancelCountdown() -> Bool {
        guard let segment = activeSegment ?? pendingCreditsSegment,
              let presentation,
              case .countdown = presentation.kind
        else { return false }

        countdownTask?.cancel()
        self.countdownTask = nil
        cancelledCountdownSegmentIDs.insert(segment.id)

        self.presentation = .init(
            kind: .nextEpisode,
            item: presentation.item,
            remainingSeconds: nil,
            countdownDurationSeconds: nil,
            countdownProgress: nil
        )
        isOverlayPresented = true

        log("Credits countdown cancelled", segment: segment)
        return true
    }

    private func playbackTimeDidChange(to current: Duration) {
        playbackTimeUpdateGeneration &+= 1
        let updateGeneration = playbackTimeUpdateGeneration
        let previous = previousSeconds

        guard currentItemID != nil else {
            previousSeconds = current
            return
        }

        if let activeSegment, !activeSegment.contains(current), current >= activeSegment.end {
            if activeSegment.type == .intro {
                dismissOverlay()
                self.activeSegment = nil
            }
        }

        evaluateCrossings(from: previous, to: current)
        // A segment action can synchronously update manager.seconds (for example,
        // an intro seek). Do not overwrite that nested update with the old time.
        if playbackTimeUpdateGeneration == updateGeneration {
            previousSeconds = current
        }
    }

    private func evaluateCrossings(from previous: Duration, to current: Duration) {
        guard current >= previous else { return }

        for segment in segments where !handledSegmentIDs.contains(segment.id) {
            // A seek can cross an entire segment in one update. Only react when
            // playback actually lands inside the segment, rather than showing a
            // stale prompt or seeking backwards after the segment has passed.
            guard segment.contains(current) else { continue }
            guard segment.startWasCrossed(from: previous, to: current) || segment.contains(previous) else { continue }

            handledSegmentIDs.insert(segment.id)
            log("Entered \(segment.type.rawValue) segment", segment: segment)

            switch segment.type {
            case .intro:
                handleIntro(segment)
            case .outro:
                handleCredits(segment)
            default:
                break
            }
        }
    }

    private func handleIntro(_ segment: ScreenPlaybackSegment) {
        switch Defaults[.VideoPlayer.Segments.introBehavior] {
        case .off:
            break
        case .showSkipButton:
            activeSegment = segment
            present(.init(
                kind: .intro,
                item: nil,
                remainingSeconds: nil,
                countdownDurationSeconds: nil,
                countdownProgress: nil
            ))
        case .autoSkip:
            seek(to: segment.end)
            log("Intro auto-skip completed", segment: segment)
        }
    }

    private func handleCredits(_ segment: ScreenPlaybackSegment) {
        switch Defaults[.VideoPlayer.Segments.creditsBehavior] {
        case .off:
            break
        case .showNextEpisode:
            activeSegment = segment
            pendingCreditsSegment = segment
            presentNextEpisodeIfAvailable(kind: .nextEpisode)
        case .countdownAutoplay:
            activeSegment = segment
            pendingCreditsSegment = segment
            startCountdownIfPossible(for: segment)
        case .immediateAutoplay:
            activeSegment = segment
            pendingCreditsSegment = segment
            if nextItemProvider != nil {
                playNextEpisode()
            } else {
                log("Immediate autoplay waiting for next-episode resolution", segment: segment)
            }
        }
    }

    private func nextItemDidResolve(_ provider: MediaPlayerItemProvider?) {
        nextItemProvider = provider
        guard let provider else {
            log("No next episode resolved")
            return
        }

        log("Resolved next episode \(provider.item.id ?? "Unknown")")
        guard let segment = pendingCreditsSegment else { return }

        switch Defaults[.VideoPlayer.Segments.creditsBehavior] {
        case .showNextEpisode:
            presentNextEpisodeIfAvailable(kind: .nextEpisode)
        case .countdownAutoplay:
            startCountdownIfPossible(for: segment)
        case .immediateAutoplay:
            playNextEpisode()
        case .off:
            break
        }
    }

    private func presentNextEpisodeIfAvailable(kind: Presentation.Kind) {
        guard let provider = nextItemProvider else {
            log("Credits overlay waiting for next-episode resolution")
            return
        }
        present(.init(
            kind: kind,
            item: provider.item,
            remainingSeconds: nil,
            countdownDurationSeconds: nil,
            countdownProgress: nil
        ))
    }

    private func startCountdownIfPossible(for segment: ScreenPlaybackSegment) {
        guard !cancelledCountdownSegmentIDs.contains(segment.id),
              countdownTask == nil,
              let provider = nextItemProvider
        else {
            if nextItemProvider == nil {
                log("Credits countdown waiting for next-episode resolution", segment: segment)
            }
            return
        }

        let duration = Defaults[.VideoPlayer.Segments.countdownDuration].rawValue
        let countdownItemID = currentItemID
        present(.init(
            kind: .countdown,
            item: provider.item,
            remainingSeconds: duration,
            countdownDurationSeconds: duration,
            countdownProgress: 0
        ))
        log("Credits countdown started at \(duration) seconds", segment: segment)

        countdownTask = Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            guard !Task.isCancelled,
                  self.currentItemID == countdownItemID,
                  self.activeSegment?.id == segment.id
            else { return }

            self.presentation = .init(
                kind: .countdown,
                item: self.nextItemProvider?.item ?? provider.item,
                remainingSeconds: duration,
                countdownDurationSeconds: duration,
                countdownProgress: 1 / Double(duration)
            )

            for remaining in stride(from: duration - 1, through: 0, by: -1) {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      self.currentItemID == countdownItemID,
                      self.activeSegment?.id == segment.id,
                      let next = self.nextItemProvider
                else { return }

                self.presentation = .init(
                    kind: .countdown,
                    item: next.item,
                    remainingSeconds: remaining,
                    countdownDurationSeconds: duration,
                    countdownProgress: Double(duration - max(remaining - 1, 0)) / Double(duration)
                )
            }

            // Background cancellation may race with the final sleep resuming.
            guard !Task.isCancelled,
                  self.currentItemID == countdownItemID,
                  self.activeSegment?.id == segment.id,
                  !self.cancelledCountdownSegmentIDs.contains(segment.id),
                  self.presentation?.kind == .countdown
            else { return }

            self.log("Credits countdown completed", segment: segment)
            self.countdownTask = nil
            self.playNextEpisode()
        }
    }

    private func seek(to seconds: Duration) {
        manager?.seconds = seconds
        manager?.proxy?.setSeconds(seconds)
    }

    private func present(_ presentation: Presentation) {
        self.presentation = presentation
        isOverlayPresented = true
    }

    private func dismissOverlay() {
        isOverlayPresented = false
        presentation = nil
    }

    private func dismissCreditsPresentation() {
        let segment = activeSegment ?? pendingCreditsSegment
        countdownTask?.cancel()
        countdownTask = nil
        activeSegment = nil
        pendingCreditsSegment = nil
        dismissOverlay()
        if let segment {
            handledSegmentIDs.insert(segment.id)
            log("Credits / Play Next presentation dismissed with Back", segment: segment)
        }
    }

    private func log(_ message: String, itemID: String? = nil) {
        manager?.logger.debug(
            "Screen segments: \(message)",
            metadata: ["itemID": .stringConvertible(itemID ?? currentItemID ?? "Unknown")]
        )
    }

    private func log(_ message: String, segment: ScreenPlaybackSegment) {
        manager?.logger.debug(
            "Screen segments: \(message)",
            metadata: [
                "itemID": .stringConvertible(currentItemID ?? "Unknown"),
                "segmentID": .stringConvertible(segment.id),
                "startSeconds": .stringConvertible(segment.start.seconds),
                "endSeconds": .stringConvertible(segment.end.seconds),
            ]
        )
    }
}

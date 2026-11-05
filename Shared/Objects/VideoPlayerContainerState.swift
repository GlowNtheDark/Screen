//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import SwiftUI

#if os(tvOS)
enum PlaybackDropdownFocusRequest: Equatable {
    case section(Int)
    case setting(Int)
    case restartEpisode
    case technicalDetailsFirstRow
}

struct PlaybackEpisodesMoveRequest: Equatable {
    enum Direction: Equatable {
        case up
        case down
    }

    let id: UUID
    let direction: Direction

    init(_ direction: Direction) {
        self.id = UUID()
        self.direction = direction
    }
}
#endif

// TODO: turned into spaghetti to get out, clean up with a better state system
// TODO: verify timer states
// TODO: for tvOS, some kind of focus token system
//       - help with Menu
//       - may help with alternate overlays

@MainActor
class VideoPlayerContainerState: ObservableObject {

    @Published
    var isAspectFilled: Bool = false

    @Published
    var isGestureLocked: Bool = false {
        didSet {
            if isGestureLocked {
                isPresentingOverlay = false
            }
        }
    }

    // TODO: rename isPresentingPlaybackButtons
    @Published
    var isPresentingPlaybackControls: Bool = false

    /// An intro/credits segment overlay currently owns tvOS remote input.
    @Published
    var isPresentingSegmentOverlay: Bool = false {
        didSet {
            if isPresentingSegmentOverlay {
                timer.stop()
            } else if !isPlaybackOverlaySurfacePresented {
                timer.poke()
            }
        }
    }

    // TODO: replace with graph dependency package
    func setPlaybackControlsVisibility() {

        guard isPresentingOverlay else {
            isPresentingPlaybackControls = false
            return
        }

        if isPresentingOverlay && !isPresentingSupplement {
            isPresentingPlaybackControls = true
            return
        }

        if isCompact {
            if isPresentingSupplement {
                if !isPresentingPlaybackControls {
                    isPresentingPlaybackControls = true
                }
            } else {
                isPresentingPlaybackControls = false
            }
        } else {
            isPresentingPlaybackControls = false
        }
    }

    @Published
    var isCompact: Bool = false {
        didSet {
            setPlaybackControlsVisibility()
        }
    }

    @Published
    var isGuestSupplement: Bool = false

    // TODO: rename isPresentingPlaybackControls
    @Published
    var isPresentingOverlay: Bool = false {
        didSet {
            setPlaybackControlsVisibility()
            presentationControllerShouldDismiss = isPresentingOverlay && !isPresentingSupplement

            if isPresentingOverlay, !isPresentingSupplement, !isPlaybackOverlaySurfacePresented {
                timer.poke()
            }
        }
    }

    @Published
    private(set) var isPresentingSupplement: Bool = false {
        didSet {
            setPlaybackControlsVisibility()
            presentationControllerShouldDismiss = isPresentingOverlay && !isPresentingSupplement

            if isPresentingSupplement {
                timer.stop()
            } else if !isPlaybackOverlaySurfacePresented {
                isGuestSupplement = false
                timer.poke()
            }
        }
    }

    @Published
    var isScrubbing: Bool = false {
        didSet {
            if isScrubbing {
                timer.stop()
            } else if !isPlaybackOverlaySurfacePresented {
                timer.poke()
            }
        }
    }

    @Published
    var presentationControllerShouldDismiss: Bool = false

    @Published
    var selectedSupplement: (any MediaPlayerSupplement)? = nil {
        didSet {
            isPresentingSupplement = selectedSupplement != nil
        }
    }

    @Published
    var isProgressBarFocused: Bool = false

    var originalPlaybackRate: Float?

    let centerOffsetBox: PublishedBox<CGFloat> = .init(initialValue: 0)
    let jumpProgressObserver: JumpProgressObserver = .init()
    let scrubbedSeconds: PublishedBox<Duration> = .init(initialValue: .zero)
    let timer: PokeIntervalTimer = .init(defaultInterval: 5)
    let toastProxy: ToastProxy = .init()

    weak var containerView: VideoPlayer.UIVideoPlayerContainerViewController?
    weak var manager: MediaPlayerManager?

    #if os(iOS)
    var panHandlingAction: (any _PanHandlingAction)?
    var didSwipe: Bool = false
    var lastTapLocation: CGPoint?
    #endif

    #if os(tvOS)
    @Published
    private(set) var presentedSupplementStyle: MediaPlayerSupplementPresentationStyle?

    @Published
    var isPresentingCloseConfirmation: Bool = false

    #if os(tvOS)
    /// The custom tvOS player dropdown is open above the video.
    @Published
    var isPresentingPlaybackDropdown: Bool = false {
        didSet {
            isPlaybackDropdownTopNavigationFocused = isPresentingPlaybackDropdown

            if isPresentingPlaybackDropdown {
                playbackDropdownSectionIndex = 0
                playbackDropdownSettingIndex = 0
                playbackDropdownFocusRequest = .section(0)
                isTechnicalDetailsContentFocused = false
                timer.stop()
            } else {
                isTechnicalDetailsContentFocused = false
                timer.poke()
            }
        }
    }

    /// The custom tvOS player Episodes shelf is open above the video.
    @Published
    var isPresentingPlaybackEpisodes: Bool = false {
        didSet {
            if isPresentingPlaybackEpisodes {
                timer.stop()
            } else if !isPresentingPlaybackDropdown {
                timer.poke()
            }
        }
    }

    /// True while focus is on the dropdown's top-level section navigation.
    @Published
    var isPlaybackDropdownTopNavigationFocused: Bool = false

    /// True while focus is on a playback setting card.
    @Published
    var isPlaybackDropdownSettingFocused: Bool = false

    /// True while focus is inside the dropdown's Technical Details rows.
    @Published
    var isTechnicalDetailsContentFocused = false

    @Published
    var playbackDropdownSectionIndex: Int = 0

    @Published
    var playbackDropdownSettingIndex: Int = 0

    @Published
    var playbackDropdownFocusRequest: PlaybackDropdownFocusRequest?

    @Published
    var playbackEpisodesMoveRequest: PlaybackEpisodesMoveRequest?

    @Published
    var isPlaybackOverlayMenuDismissalGuarded = false

    func closePlaybackDropdownForMenuPress() -> Bool {
        guard isPresentingPlaybackDropdown else { return false }

        isPlaybackOverlayMenuDismissalGuarded = true

        if isTechnicalDetailsContentFocused {
            isTechnicalDetailsContentFocused = false
            isPlaybackDropdownTopNavigationFocused = true
            playbackDropdownFocusRequest = .section(playbackDropdownSectionIndex)
            return true
        }

        isPresentingPlaybackDropdown = false
        return true
    }
    #endif

    func commitScrub() {
        guard isScrubbing else { return }

        #if os(tvOS)
        let target = clampedScrubTarget(scrubbedSeconds.value)
        if target != scrubbedSeconds.value {
            scrubbedSeconds.value = target
        }
        #else
        let target = scrubbedSeconds.value
        #endif

        manager?.seconds = target
        if let proxy = manager?.proxy {
            proxy.setSeconds(target)
        }
        isScrubbing = false
    }

    #if os(tvOS)
    func clampedScrubTarget(_ seconds: Duration) -> Duration {
        guard let runtime = manager?.item.runtime, runtime > .zero else { return .zero }

        let upperBound = (manager?.proxy as? VLCMediaPlayerProxy)?.scrubSeekUpperBound(for: runtime) ?? runtime
        return clamp(seconds, min: .zero, max: upperBound)
    }
    #endif

    func cancelScrub() {
        guard isScrubbing else { return }

        if let manager {
            scrubbedSeconds.value = manager.seconds
        }

        isScrubbing = false
    }

    func setPresentedSupplementStyle(_ style: MediaPlayerSupplementPresentationStyle?) {
        presentedSupplementStyle = style
    }
    #endif

    private var jumpProgressCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?

    private var isPlaybackOverlaySurfacePresented: Bool {
        #if os(tvOS)
        isPresentingPlaybackDropdown || isPresentingPlaybackEpisodes || isPresentingSegmentOverlay
        #else
        false
        #endif
    }

    init() {
        timerCancellable = timer.sink { [weak self] in
            guard let self else { return }
            guard !isScrubbing,
                  !isPresentingSupplement,
                  !isPresentingSegmentOverlay,
                  !isPlaybackOverlaySurfacePresented,
                  manager?.playbackRequestStatus != .paused
            else { return }

            withAnimation(.linear(duration: 0.25)) {
                self.isPresentingOverlay = false
            }
        }

        #if os(iOS)
        jumpProgressCancellable = jumpProgressObserver
            .timer
            .sink { [weak self] in
                self?.lastTapLocation = nil
            }
        #endif
    }

    func select(supplement: (any MediaPlayerSupplement)?, isGuest: Bool = false) {
        isGuestSupplement = isGuest

        if supplement?.id == selectedSupplement?.id {
            selectedSupplement = nil
            containerView?.presentSupplementContainer(false)
        } else {
            selectedSupplement = supplement
            containerView?.presentSupplementContainer(
                supplement != nil,
                presentationStyle: isGuest ? supplement?.presentationStyle : nil
            )
        }
    }
}

//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Logging
import MediaPlayer
import SwiftUI

// TODO: don't dismiss overlay while panning and supplement not presented
// TODO: use video size from proxies to control aspect fill
//       - stay within safe areas, aspect fill to screen
// TODO: instead of static sizes for supplement view, take into account available space
//       - necessary for full-screen supplements and/or small screens
// TODO: custom buttons on playback controls
//       - skip intro, next episode, etc.
//       - can just do on playback controls itself
// TODO: pass in safe area insets explicitly?
// TODO: pause when center tapped when overlay dismissed
//       - can be done entirely on playback controls layer
// TODO: no supplements state
//       - don't pan
// TODO: account for gesture state active when item changes
// TODO: only show player view if not error/other bad states
//       - only show when have item?
//       - helps with not rendering before ready
//       - would require refactor so that video players take media player items

// MARK: - VideoPlayerContainerView

extension VideoPlayer {

    struct VideoPlayerContainerView<Player: View, PlaybackControls: View>: PlatformViewControllerRepresentable {

        private let containerState: VideoPlayerContainerState
        private let manager: MediaPlayerManager
        private let onPresentationWillStopPlayback: () -> Void
        private let player: Player
        private let playbackControls: PlaybackControls
        private let segmentOverlay: () -> AnyView

        init(
            containerState: VideoPlayerContainerState,
            manager: MediaPlayerManager,
            onPresentationWillStopPlayback: @escaping () -> Void,
            @ViewBuilder player: @escaping () -> Player,
            @ViewBuilder playbackControls: @escaping () -> PlaybackControls,
            segmentOverlay: @escaping () -> AnyView = { AnyView(EmptyView()) }
        ) {
            self.containerState = containerState
            self.manager = manager
            self.onPresentationWillStopPlayback = onPresentationWillStopPlayback
            self.player = player()
            self.playbackControls = playbackControls()
            self.segmentOverlay = segmentOverlay
        }

        func makeUIViewController(context: Context) -> UIVideoPlayerContainerViewController {
            let playerView = player
                .environment(\.audioOffset, context.environment.audioOffset)
                .eraseToAnyView()

            let playbackControlsView = playbackControls
                .environment(\.audioOffset, context.environment.audioOffset)
                .eraseToAnyView()

            let segmentOverlayView = segmentOverlay()
                .environment(\.audioOffset, context.environment.audioOffset)
                .environmentObject(containerState)
                .environmentObject(manager)
                .eraseToAnyView()

            return UIVideoPlayerContainerViewController(
                containerState: containerState,
                manager: manager,
                onPresentationWillStopPlayback: onPresentationWillStopPlayback,
                player: playerView,
                playbackControls: playbackControlsView,
                segmentOverlay: segmentOverlayView
            )
        }

        func updateUIViewController(
            _ uiViewController: UIVideoPlayerContainerViewController,
            context: Context
        ) {}
    }

    // MARK: - UIVideoPlayerContainerViewController

    class UIVideoPlayerContainerViewController: UIViewController {

        // MARK: - Views

        // TODO: preview image while scrubbing option
        private struct PlayerContainerView: View {

            @EnvironmentObject
            private var containerState: VideoPlayerContainerState

            let player: AnyView

            private var shouldPresentDimOverlay: Bool {
                if containerState.isScrubbing {
                    return false
                }

                if containerState.isCompact {
                    return containerState.isPresentingPlaybackControls
                } else {
                    return containerState.isPresentingOverlay
                }
            }

            private var presentedSupplementStyle: MediaPlayerSupplementPresentationStyle? {
                #if os(tvOS)
                containerState.presentedSupplementStyle
                #else
                containerState.selectedSupplement?.presentationStyle
                #endif
            }

            var body: some View {
                player
                    #if os(iOS)
                        .overlay(Color.black.opacity(shouldPresentDimOverlay ? 0.5 : 0.0))
                    #endif
                    .overlay {
                        Group {
                            if presentedSupplementStyle == .expanded {
                                Color.black.opacity(0.8)
                            } else {
                                EasedGradient(
                                    colors: [.clear, .black],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                            }
                        }
                        .isVisible(shouldPresentDimOverlay)
                    }
                    .allowsHitTesting(false)
            }
        }

        private struct PlaybackControlsContainerView: View {

            @EnvironmentObject
            private var containerState: VideoPlayerContainerState

            let playbackControls: AnyView

            var body: some View {
                OverlayToastView(proxy: containerState.toastProxy) {
                    Group {
                        #if os(iOS)
                        ZStack {
                            GestureView()
                                .environment(
                                    \.panGestureDirection,
                                    containerState.isPresentingSupplement
                                        ? .vertical
                                        : (containerState.isPresentingOverlay ? .up : .allButDown)
                                )

                            playbackControls
                        }
                        #else
                        playbackControls
                        #endif
                    }
                    .environmentObject(containerState.scrubbedSeconds)
                    .environmentObject(containerState.centerOffsetBox)
                }
                #if os(iOS)
                .environment(
                        \.longPressAction,
                        .init(
                            action: {
                                containerState.containerView?.handleLongPressGesture(
                                    location: $0,
                                    unitPoint: $1,
                                    state: $2
                                )
                            }
                        )
                    )
                    .environment(
                        \.panAction,
                        .init(
                            action: {
                                containerState.containerView?.handlePanGesture(
                                    translation: $0,
                                    velocity: $1,
                                    location: $2,
                                    unitPoint: $3,
                                    state: $4
                                )
                            }
                        )
                    )
                    .environment(
                        \.pinchAction,
                        .init(
                            action: {
                                containerState.containerView?.handlePinchGesture(scale: $0, velocity: $1, state: $2)
                            }
                        )
                    )
                    .environment(
                        \.tapGestureAction,
                        .init(
                            action: {
                                containerState.containerView?.handleTapGesture(
                                    location: $0,
                                    unitPoint: $1,
                                    count: $2
                                )
                            }
                        )
                    )
                #endif
            }
        }

        private lazy var initialHitBlockView: UIView = {
            let view = UIView(frame: .zero)
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }()

        private lazy var playerViewController: HostingController<AnyView> = {
            let controller = HostingController(
                content: PlayerContainerView(player: player)
                    .environmentObject(containerState)
                    .environmentObject(manager)
                    .eraseToAnyView()
            )
            controller.disableSafeArea = true
            controller.automaticallyAllowUIKitAnimationsForNextUpdate = true
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            return controller
        }()

        private lazy var playbackControlsViewController: HostingController<AnyView> = {
            let controller = HostingController(
                content: PlaybackControlsContainerView(playbackControls: playbackControls)
                    .environmentObject(containerState)
                    .environmentObject(manager)
                    .eraseToAnyView()
            )
            controller.disableSafeArea = true
            controller.automaticallyAllowUIKitAnimationsForNextUpdate = true
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            return controller
        }()

        private lazy var segmentOverlayViewController: HostingController<AnyView> = {
            let controller = HostingController(
                content: segmentOverlay
                    .environmentObject(containerState)
                    .environmentObject(manager)
                    .eraseToAnyView()
            )
            controller.disableSafeArea = true
            controller.automaticallyAllowUIKitAnimationsForNextUpdate = true
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            return controller
        }()

        override var preferredFocusEnvironments: [UIFocusEnvironment] {
            #if os(tvOS)
            if containerState.isPresentingSegmentOverlay {
                return [segmentOverlayViewController]
            }

            let isPlaybackControlSurfacePresented = containerState.isPresentingPlaybackDropdown ||
                containerState.isPresentingPlaybackEpisodes ||
                (containerState.isPresentingOverlay &&
                    !containerState.isPresentingSupplement &&
                    !containerState.isPresentingSegmentOverlay)

            if isPlaybackControlSurfacePresented {
                return [playbackControlsViewController]
            }
            #endif
            return super.preferredFocusEnvironments
        }

        private lazy var supplementContainerViewController: HostingController<AnyView> = {
            let content = SupplementContainerView()
                .environmentObject(containerState)
                .environmentObject(manager)
                .eraseToAnyView()
            let controller = HostingController(content: content)
            controller.disableSafeArea = true
            controller.automaticallyAllowUIKitAnimationsForNextUpdate = true
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            return controller
        }()

        private var playerView: UIView {
            playerViewController.view
        }

        private var playbackControlsView: UIView {
            playbackControlsViewController.view
        }

        private var segmentOverlayView: UIView {
            segmentOverlayViewController.view
        }

        private var supplementContainerView: UIView {
            supplementContainerViewController.view
        }

        // MARK: - Constants

        private let compactSupplementContainerOffset: (CGFloat) -> CGFloat = { totalHeight in
            max(totalHeight * 0.6, 300) + EdgeInsets.edgePadding * 2
        }

        private func regularSupplementContainerOffset(_ totalHeight: CGFloat) -> CGFloat {
            if UIDevice.isTV {
                totalHeight / 3 + EdgeInsets.edgePadding * 2
            } else {
                200.0 + EdgeInsets.edgePadding * 2
            }
        }

        private func supplementContainerOffset(
            for totalHeight: CGFloat,
            isCompact: Bool? = nil
        ) -> CGFloat {
            let isCompact = isCompact ?? containerState.isCompact
            let regularOffset = isCompact
                ? compactSupplementContainerOffset(totalHeight)
                : regularSupplementContainerOffset(totalHeight)

            guard !isCompact,
                  presentedSupplementStyle == .expanded
            else {
                return regularOffset
            }

            return totalHeight
        }

        private var presentedSupplementStyle: MediaPlayerSupplementPresentationStyle? {
            #if os(tvOS)
            containerState.presentedSupplementStyle
            #else
            containerState.selectedSupplement?.presentationStyle
            #endif
        }

        private var dismissedSupplementContainerOffset: CGFloat {
            UIDevice.isTV ? 120 : 50.0 + EdgeInsets.edgePadding * 2
        }

        private let compactMinimumTranslation: CGFloat = 100.0
        private let regularMinimumTranslation: CGFloat = 50.0

        // MARK: - Constraints

        private var playbackControlsConstraints: [NSLayoutConstraint] = []
        private var playerCompactConstraints: [NSLayoutConstraint] = []
        private var playerRegularConstraints: [NSLayoutConstraint] = []
        private var supplementContainerConstraints: [NSLayoutConstraint] = []

        private var playerCompactBottomAnchor: NSLayoutConstraint?
        private var supplementHeightAnchor: NSLayoutConstraint?
        private var supplementBottomAnchor: NSLayoutConstraint?

        private var centerOffset: CGFloat {
            guard containerState.isCompact,
                  let supplementBottomAnchor,
                  let supplementHeightAnchor
            else {
                return dismissedSupplementContainerOffset
            }

            let supplementContainerHeight = supplementHeightAnchor.constant
            let offsetPercentage = 1 - clamp(supplementBottomAnchor.constant.magnitude / supplementContainerHeight, min: 0, max: 1)
            let offset = (dismissedSupplementContainerOffset + EdgeInsets.edgePadding) * offsetPercentage

            return max(50, offset)
        }

        private var compactPlayerBottomOffset: CGFloat {
            guard containerState.isCompact,
                  let supplementBottomAnchor,
                  let supplementHeightAnchor
            else {
                return dismissedSupplementContainerOffset
            }
            let supplementContainerHeight = supplementHeightAnchor.constant
            let offsetPercentage = 1 - clamp(supplementBottomAnchor.constant.magnitude / supplementContainerHeight, min: 0, max: 1)
            return (dismissedSupplementContainerOffset + EdgeInsets.edgePadding) * offsetPercentage
        }

        private let logger = Logger.screen()
        private let manager: MediaPlayerManager
        private let onPresentationWillStopPlayback: () -> Void
        private let player: AnyView
        private let playbackControls: AnyView
        private let segmentOverlay: AnyView
        let containerState: VideoPlayerContainerState
        private let playbackContentView = UIView()

        private var cancellables: Set<AnyCancellable> = []
        private var didInitiallyAppear: Bool = false

        #if os(tvOS)
        let onPressEvent = OnPressEvent()
        #endif

        init(
            containerState: VideoPlayerContainerState,
            manager: MediaPlayerManager,
            onPresentationWillStopPlayback: @escaping () -> Void,
            player: AnyView,
            playbackControls: AnyView,
            segmentOverlay: AnyView
        ) {
            self.containerState = containerState
            self.manager = manager
            self.onPresentationWillStopPlayback = onPresentationWillStopPlayback
            self.player = player
            self.playbackControls = playbackControls
            self.segmentOverlay = segmentOverlay

            super.init(nibName: nil, bundle: nil)

            containerState.containerView = self
            containerState.manager = manager
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // TODO: don't force unwrap optional, sometimes gets into weird state
        private var lastVerticalPanLocation: CGPoint?
        private var verticalPanGestureStartConstant: CGFloat?
        private var isPanning: Bool = false
        private var didStartPanningWithSupplement: Bool = false
        private var didStartPanningUpWithoutOverlay: Bool = false
        #if os(tvOS)
        private var playbackScrubPanStartSeconds: Duration?
        private var playbackScrubPanItemID: String?
        private let playbackScrubPanDampingValue: CGFloat = 200
        #endif

        // MARK: - Supplement Pan Action

        func handleSupplementPanAction(
            translation: CGPoint,
            velocity: CGFloat,
            location: CGPoint,
            state: UIGestureRecognizer.State
        ) {
            #if os(tvOS)
            guard !containerState.isPresentingPlaybackDropdown,
                  !containerState.isPresentingPlaybackEpisodes
            else { return }

            if state == .began {
                self.playbackContentView.layer.removeAllAnimations()
                didStartPanningWithSupplement = containerState.selectedSupplement != nil

                if !didStartPanningWithSupplement {
                    didStartPanningUpWithoutOverlay = !containerState.isPresentingOverlay
                    if didStartPanningUpWithoutOverlay {
                        containerState.isPresentingOverlay = true
                    }
                }
            }

            if !didStartPanningWithSupplement {
                if state == .ended {
                    let translationMin: CGFloat = containerState.isCompact ? compactMinimumTranslation : regularMinimumTranslation
                    let didSwipeUpToEpisodes = !didStartPanningUpWithoutOverlay &&
                        (translation.y < -translationMin || velocity < -1000) &&
                        manager.queue?.episodeQueue != nil

                    if didSwipeUpToEpisodes {
                        containerState.isPresentingPlaybackEpisodes = true
                    }

                    didStartPanningUpWithoutOverlay = false
                } else if state == .cancelled {
                    didStartPanningUpWithoutOverlay = false
                }

                return
            }
            #endif

            guard let supplementBottomAnchor,
                  let supplementHeightAnchor,
                  let playerCompactBottomAnchor
            else { return }

            let yDirection: CGFloat = translation.y > 0 ? -1 : 1
            let newOffset: CGFloat
            let clampedOffset: CGFloat

            if state == .began {
                self.playbackContentView.layer.removeAllAnimations()
                didStartPanningWithSupplement = containerState.selectedSupplement != nil
                verticalPanGestureStartConstant = supplementBottomAnchor.constant
                didStartPanningUpWithoutOverlay = !containerState.isPresentingOverlay
                if didStartPanningUpWithoutOverlay {
                    containerState.isPresentingOverlay = true
                }
            }

            if state == .began || state == .changed {
                lastVerticalPanLocation = location
                isPanning = true

                let minimumTranslation =
                    -((containerState.isCompact ? compactMinimumTranslation : regularMinimumTranslation) +
                        dismissedSupplementContainerOffset
                    )
                let shouldHaveSupplementPresented = supplementBottomAnchor.constant < minimumTranslation

                if shouldHaveSupplementPresented, !containerState.isPresentingSupplement {
                    containerState.selectedSupplement = manager.supplements.first
                } else if !shouldHaveSupplementPresented, containerState.selectedSupplement != nil {
                    containerState.selectedSupplement = nil
                }
            } else {
                lastVerticalPanLocation = nil
                verticalPanGestureStartConstant = nil
                isPanning = false

                let translationMin: CGFloat = containerState.isCompact ? compactMinimumTranslation : regularMinimumTranslation
                let shouldActuallyDismissSupplement = didStartPanningWithSupplement && (translation.y > translationMin || velocity > 1000)
                if shouldActuallyDismissSupplement {
                    // If we started with a supplement and panned down more than 100 points, dismiss it
                    containerState.selectedSupplement = nil
                }

                let shouldActuallyPresentSupplement = !didStartPanningWithSupplement &&
                    (translation.y < -translationMin || velocity < -1000)
                if shouldActuallyPresentSupplement {
                    // If we didn't start with a supplement and panned up more than 100 points, present it
                    containerState.selectedSupplement = manager.supplements.first
                }

                let stateToPass: (translation: CGFloat, velocity: CGFloat)? = lastVerticalPanLocation != nil &&
                    verticalPanGestureStartConstant !=
                    nil ?
                    (translation: translation.y, velocity: velocity) : nil
                presentSupplementContainer(containerState.selectedSupplement != nil, with: stateToPass)

                let shouldActuallyDismissOverlay = didStartPanningUpWithoutOverlay && !containerState.isPresentingSupplement

                if shouldActuallyDismissOverlay {
                    containerState.isPresentingOverlay = false
                }
                return
            }

            guard let verticalPanGestureStartConstant else {
                logger.error("Vertical pan gesture invalid state: verticalPanGestureStartConstant is nil")
                return
            }

            if (!didStartPanningWithSupplement && yDirection > 0) || (didStartPanningWithSupplement && yDirection < 0) {
                // If we started with a supplement and are panning down, or if we didn't start with a supplement and are panning up
                newOffset = verticalPanGestureStartConstant + (translation.y.magnitude * -yDirection)
            } else {
                newOffset = verticalPanGestureStartConstant - (translation.y.magnitude * yDirection)
            }

            clampedOffset = clamp(
                newOffset,
                min: -supplementHeightAnchor.constant,
                max: -dismissedSupplementContainerOffset
            )

            if newOffset < clampedOffset {
                let excess = clampedOffset - newOffset
                let resistance = pow(excess, 0.7)
                supplementBottomAnchor.constant = clampedOffset - resistance
            } else if newOffset > -dismissedSupplementContainerOffset {
                let excess = newOffset - clampedOffset
                let resistance = pow(excess, 0.5)
                supplementBottomAnchor.constant = clamp(clampedOffset + resistance, min: -dismissedSupplementContainerOffset, max: -50)
            } else {
                supplementBottomAnchor.constant = clampedOffset
            }

            playerCompactBottomAnchor.constant = compactPlayerBottomOffset
            containerState.centerOffsetBox.value = centerOffset
        }

        // MARK: - present

        func presentSupplementContainer(
            _ didPresent: Bool,
            with panningState: (translation: CGFloat, velocity: CGFloat)? = nil,
            presentationStyle: MediaPlayerSupplementPresentationStyle? = nil
        ) {
            guard !isPanning else { return }
            guard let supplementBottomAnchor,
                  let supplementHeightAnchor,
                  let playerCompactBottomAnchor
            else { return }

            #if os(tvOS)
            if !didPresent || presentationStyle != nil {
                containerState.setPresentedSupplementStyle(didPresent ? presentationStyle : nil)
            }
            #endif

            if didPresent {
                let presentedOffset = supplementContainerOffset(for: view.bounds.height)
                supplementHeightAnchor.constant = presentedOffset
                supplementBottomAnchor.constant = -presentedOffset
            } else {
                supplementBottomAnchor.constant = -dismissedSupplementContainerOffset
            }

            playerCompactBottomAnchor.constant = compactPlayerBottomOffset
            containerState.centerOffsetBox.value = centerOffset

            if let panningState {
                let velocity = panningState.velocity.magnitude / 1000
                let distance = panningState.translation.magnitude
                let duration = min(max(Double(distance) / Double(velocity * 1000), 0.2), 0.75)

                UIView.animate(
                    withDuration: duration,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: velocity,
                    options: .allowUserInteraction
                ) { [weak self] in
                    self?.view.layoutIfNeeded()
                }
            } else {
                UIView.animate(
                    withDuration: containerState.isCompact ? 0.75 : 0.6,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0.4,
                    options: .allowUserInteraction
                ) { [weak self] in
                    self?.view.layoutIfNeeded()
                }
            }
        }

        // MARK: - viewDidAppear

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)

            if !didInitiallyAppear {
                containerState.isPresentingOverlay = true
                setupPlayerView()
                initialHitBlockView.removeFromSuperview()
                didInitiallyAppear = true
            }

            #if os(tvOS)
            Task { @MainActor in
                disableTogglePlayPauseCommand()
            }
            #endif
        }

        // MARK: - viewDidLoad

        override func viewDidLoad() {
            super.viewDidLoad()

            view.backgroundColor = .clear
            playbackContentView.backgroundColor = .black

            let isCompact = UIDevice.isPhone && view.bounds.size.isPortrait

            setupOnLoadViews()
            setupOnLoadConstraints()

            Task { @MainActor in
                containerState.isCompact = isCompact
                containerState.centerOffsetBox.value = centerOffset
            }

            #if os(tvOS)
            let scrubPan = DirectionalPanGestureRecognizer(
                direction: .horizontal,
                target: self,
                action: #selector(handlePlaybackScrubPan(_:))
            )
            scrubPan.delegate = self
            view.addGestureRecognizer(scrubPan)

            for direction in [UISwipeGestureRecognizer.Direction.up, .down] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handlePlaybackSwipe(_:)))
                swipe.direction = direction
                swipe.delegate = self
                view.addGestureRecognizer(swipe)
            }

            containerState.$isPresentingOverlay
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isPresenting in
                    guard let self else { return }
                    self.supplementContainerView.isUserInteractionEnabled =
                        isPresenting &&
                        !self.containerState.isPresentingPlaybackDropdown &&
                        !self.containerState.isPresentingPlaybackEpisodes

                    let shouldFocusPlaybackHUD = isPresenting &&
                        !self.containerState.isPresentingSupplement &&
                        !self.containerState.isPresentingPlaybackDropdown &&
                        !self.containerState.isPresentingPlaybackEpisodes &&
                        !self.containerState.isPresentingSegmentOverlay

                    if shouldFocusPlaybackHUD {
                        self.setNeedsFocusUpdate()
                        self.updateFocusIfNeeded()
                    }
                }
                .store(in: &cancellables)

            containerState.$isPresentingSegmentOverlay
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isPresenting in
                    guard let self else { return }
                    self.segmentOverlayView.isUserInteractionEnabled = isPresenting
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
                .store(in: &cancellables)

            manager.screenSegmentCoordinator.$presentation
                .receive(on: DispatchQueue.main)
                .sink { [weak self] presentation in
                    guard let self else { return }
                    let isNextEpisodeTransition: Bool = if let presentation {
                        switch presentation.kind {
                        case .intro:
                            false
                        case .nextEpisode, .countdown:
                            true
                        }
                    } else {
                        false
                    }

                    let transform = CGAffineTransform(
                        scaleX: isNextEpisodeTransition ? 0.72 : 1,
                        y: isNextEpisodeTransition ? 0.72 : 1
                    )
                    let alpha: CGFloat = isNextEpisodeTransition ? 0.5 : 1
                    UIView.animate(
                        withDuration: 0.3,
                        delay: 0,
                        options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut]
                    ) {
                        self.playbackContentView.transform = transform
                        self.playbackContentView.alpha = alpha
                    }
                }
                .store(in: &cancellables)

            containerState.$isPresentingPlaybackDropdown
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isPresenting in
                    guard let self else { return }
                    let isAnotherPlaybackSurfacePresented = isPresenting || self.containerState.isPresentingPlaybackEpisodes
                    self.supplementContainerView.isHidden = isAnotherPlaybackSurfacePresented
                    self.supplementContainerView.isUserInteractionEnabled =
                        !isAnotherPlaybackSurfacePresented && self.containerState.isPresentingOverlay
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
                .store(in: &cancellables)

            containerState.$isPresentingPlaybackEpisodes
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isPresenting in
                    guard let self else { return }
                    #if DEBUG
                    EpisodePlaybackDiagnostics.logEpisodesBack(
                        self.manager.episodePlaybackDiagnosticID,
                        event: "episodes-state-published isPresentingPlaybackEpisodes=\(isPresenting)"
                    )
                    #endif
                    let isAnotherPlaybackSurfacePresented = isPresenting || self.containerState.isPresentingPlaybackDropdown
                    self.supplementContainerView.isHidden = isAnotherPlaybackSurfacePresented
                    self.supplementContainerView.isUserInteractionEnabled =
                        !isAnotherPlaybackSurfacePresented && self.containerState.isPresentingOverlay
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
                .store(in: &cancellables)
            #endif
        }

        // Setup player view separately after view appears to hopefully
        // prevent player playing before the view is done presenting
        private func setupPlayerView() {
            addChild(playerViewController)
            playbackContentView.addSubview(playerView)
            playbackContentView.sendSubviewToBack(playerView)
            playerViewController.didMove(toParent: self)
            playerView.backgroundColor = .black

            let bottomAnchor = playerView.bottomAnchor.constraint(
                equalTo: supplementContainerView.topAnchor,
                constant: compactPlayerBottomOffset
            )

            playerCompactBottomAnchor = bottomAnchor

            playerCompactConstraints = [
                playerView.leadingAnchor.constraint(equalTo: playbackContentView.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: playbackContentView.trailingAnchor),
                playerView.topAnchor.constraint(equalTo: playbackContentView.topAnchor),
                bottomAnchor,
            ]
            playerRegularConstraints = [
                playerView.leadingAnchor.constraint(equalTo: playbackContentView.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: playbackContentView.trailingAnchor),
                playerView.topAnchor.constraint(equalTo: playbackContentView.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: playbackContentView.bottomAnchor),
            ]

            if containerState.isCompact {
                NSLayoutConstraint.activate(playerCompactConstraints)
            } else {
                NSLayoutConstraint.activate(playerRegularConstraints)
            }
        }

        private func setupOnLoadViews() {
            view.addSubview(playbackContentView)
            playbackContentView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                playbackContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                playbackContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                playbackContentView.topAnchor.constraint(equalTo: view.topAnchor),
                playbackContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            addChild(playbackControlsViewController)
            playbackContentView.addSubview(playbackControlsView)
            playbackControlsViewController.didMove(toParent: self)
            playbackControlsView.backgroundColor = .clear

            addChild(supplementContainerViewController)
            playbackContentView.addSubview(supplementContainerView)
            supplementContainerViewController.didMove(toParent: self)
            supplementContainerView.backgroundColor = .clear

            playbackContentView.addSubview(initialHitBlockView)
            playbackContentView.bringSubviewToFront(initialHitBlockView)

            addChild(segmentOverlayViewController)
            view.addSubview(segmentOverlayView)
            segmentOverlayViewController.didMove(toParent: self)
            segmentOverlayView.backgroundColor = .clear
            segmentOverlayView.isUserInteractionEnabled = containerState.isPresentingSegmentOverlay
            view.bringSubviewToFront(segmentOverlayView)
        }

        private func setupOnLoadConstraints() {

            let isCompact = UIDevice.isPhone && view.bounds.size.isPortrait

            let bottomAnchor = supplementContainerView.topAnchor.constraint(
                equalTo: playbackContentView.bottomAnchor,
                constant: -dismissedSupplementContainerOffset
            )
            supplementBottomAnchor = bottomAnchor

            let constant = supplementContainerOffset(
                for: playbackContentView.bounds.height,
                isCompact: isCompact
            )
            let heightAnchor = supplementContainerView.heightAnchor.constraint(equalToConstant: constant)
            supplementHeightAnchor = heightAnchor

            supplementContainerConstraints = [
                supplementContainerView.leadingAnchor.constraint(equalTo: playbackContentView.leadingAnchor),
                supplementContainerView.trailingAnchor.constraint(equalTo: playbackContentView.trailingAnchor),
                bottomAnchor,
                heightAnchor,
            ]

            NSLayoutConstraint.activate(supplementContainerConstraints)

            #if os(tvOS)
            let playbackControlsBottomAnchor = playbackControlsView.bottomAnchor.constraint(
                equalTo: playbackContentView.bottomAnchor,
                constant: -dismissedSupplementContainerOffset
            )
            #else
            let playbackControlsBottomAnchor = playbackControlsView.bottomAnchor.constraint(
                equalTo: supplementContainerView.topAnchor
            )
            #endif

            playbackControlsConstraints = [
                playbackControlsView.leadingAnchor.constraint(equalTo: playbackContentView.leadingAnchor),
                playbackControlsView.trailingAnchor.constraint(equalTo: playbackContentView.trailingAnchor),
                playbackControlsView.topAnchor.constraint(equalTo: playbackContentView.topAnchor),
                playbackControlsBottomAnchor,
            ]

            NSLayoutConstraint.activate(playbackControlsConstraints)

            NSLayoutConstraint.activate([
                segmentOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                segmentOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                segmentOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
                segmentOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            NSLayoutConstraint.activate([
                initialHitBlockView.topAnchor.constraint(equalTo: playbackContentView.topAnchor),
                initialHitBlockView.leadingAnchor.constraint(equalTo: playbackContentView.leadingAnchor),
                initialHitBlockView.trailingAnchor.constraint(equalTo: playbackContentView.trailingAnchor),
                initialHitBlockView.bottomAnchor.constraint(equalTo: playbackContentView.bottomAnchor),
            ])
        }

        override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            adjustContraints(isCompact: UIDevice.isPhone && size.isPortrait, in: size)
        }

        private func adjustContraints(isCompact: Bool, in newSize: CGSize) {
            containerState.isCompact = isCompact

            guard let supplementBottomAnchor,
                  let supplementHeightAnchor,
                  let playerCompactBottomAnchor
            else { return }

            let presentedOffset = supplementContainerOffset(
                for: newSize.height,
                isCompact: isCompact
            )

            if isCompact {
                NSLayoutConstraint.deactivate(playerRegularConstraints)
                NSLayoutConstraint.activate(playerCompactConstraints)
            } else {
                NSLayoutConstraint.deactivate(playerCompactConstraints)
                NSLayoutConstraint.activate(playerRegularConstraints)
            }

            supplementBottomAnchor.constant = containerState
                .isPresentingSupplement ? -presentedOffset : -dismissedSupplementContainerOffset
            supplementHeightAnchor.constant = presentedOffset

            playerCompactBottomAnchor.constant = compactPlayerBottomOffset
            containerState.centerOffsetBox.value = centerOffset
        }

        // MARK: - tvOS

        #if os(tvOS)
        /// Handle view disappearance since tvOS this can be done in non-standard ways
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)

            #if DEBUG
            EpisodePlaybackDiagnostics.log(
                manager.episodePlaybackDiagnosticID,
                event: "player-view-will-disappear managerState=\(String(describing: manager.state))"
            )
            EpisodePlaybackDiagnostics.logEpisodesBack(
                manager.episodePlaybackDiagnosticID,
                event: "player-view-will-disappear episodes=\(containerState.isPresentingPlaybackEpisodes)"
            )
            #endif
            guard manager.state != .stopped else { return }

            onPresentationWillStopPlayback()
            Task { @MainActor in
                #if DEBUG
                EpisodePlaybackDiagnostics.log(
                    manager.episodePlaybackDiagnosticID,
                    event: "presentation-disappearance-stop-request"
                )
                #endif
                manager.stop()
            }
        }

        private func disableTogglePlayPauseCommand() {
            let command = MPRemoteCommandCenter.shared().togglePlayPauseCommand
            command.removeTarget(nil)
            command.addTarget { _ in .success }
        }

        @objc
        private func handlePlaybackScrubPan(_ gestureRecognizer: DirectionalPanGestureRecognizer) {
            switch gestureRecognizer.state {
            case .began:
                guard canBeginBackgroundPlaybackScrub else { return }

                playbackScrubPanStartSeconds = manager.seconds
                playbackScrubPanItemID = manager.item.id
                containerState.scrubbedSeconds.value = manager.seconds
                containerState.isScrubbing = true
                containerState.isPresentingOverlay = true
                #if DEBUG
                PlaybackScrubDiagnostics.log("background-pan-began current=\(manager.seconds)")
                #endif
            case .changed:
                guard let playbackScrubPanStartSeconds else { return }
                guard canContinueBackgroundPlaybackScrub,
                      let runtime = manager.item.runtime
                else {
                    cancelBackgroundPlaybackScrub()
                    return
                }

                let translation = gestureRecognizer.translation(in: view).x
                let requestedSeconds = playbackScrubPanStartSeconds.seconds +
                    Double(translation / playbackScrubPanDampingValue) * runtime.seconds
                let clampedSeconds = clamp(requestedSeconds, min: 0, max: runtime.seconds)
                containerState.scrubbedSeconds.value = .seconds(clampedSeconds)
                #if DEBUG
                PlaybackScrubDiagnostics.log("background-pan-changed pending=\(containerState.scrubbedSeconds.value)")
                #endif
            case .ended:
                guard playbackScrubPanStartSeconds != nil else { return }
                #if DEBUG
                PlaybackScrubDiagnostics.log("background-pan-ended pending=\(containerState.scrubbedSeconds.value)")
                #endif
                guard canContinueBackgroundPlaybackScrub else {
                    cancelBackgroundPlaybackScrub()
                    return
                }
                playbackScrubPanStartSeconds = nil
                playbackScrubPanItemID = nil
                containerState.commitScrub()
            case .cancelled, .failed:
                guard playbackScrubPanStartSeconds != nil else { return }
                cancelBackgroundPlaybackScrub()
            default:
                break
            }
        }

        private var canBeginBackgroundPlaybackScrub: Bool {
            guard !containerState.isPresentingOverlay,
                  !containerState.isScrubbing,
                  !containerState.isPresentingSupplement,
                  !containerState.isPresentingPlaybackDropdown,
                  !containerState.isPresentingPlaybackEpisodes,
                  !containerState.isPresentingSegmentOverlay,
                  !containerState.isPresentingCloseConfirmation,
                  !containerState.isPlaybackOverlayMenuDismissalGuarded,
                  manager.state != .loadingItem,
                  !manager.item.isLiveStream,
                  let runtime = manager.item.runtime,
                  runtime > .zero,
                  !hasPresentedChild(in: self)
            else { return false }

            return true
        }

        private var canContinueBackgroundPlaybackScrub: Bool {
            containerState.isScrubbing &&
                !containerState.isPresentingSupplement &&
                !containerState.isPresentingPlaybackDropdown &&
                !containerState.isPresentingPlaybackEpisodes &&
                !containerState.isPresentingSegmentOverlay &&
                !containerState.isPresentingCloseConfirmation &&
                !containerState.isPlaybackOverlayMenuDismissalGuarded &&
                manager.state != .loadingItem &&
                !manager.item.isLiveStream &&
                manager.item.id == playbackScrubPanItemID &&
                manager.item.runtime.map { $0 > .zero } == true &&
                !hasPresentedChild(in: self)
        }

        private func cancelBackgroundPlaybackScrub() {
            playbackScrubPanStartSeconds = nil
            playbackScrubPanItemID = nil
            #if DEBUG
            PlaybackScrubDiagnostics.log("background-pan-cancelled pending=\(containerState.scrubbedSeconds.value)")
            #endif
            containerState.cancelScrub()
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)

            if containerState.isPresentingOverlay {
                containerState.timer.poke()
            }
        }

        @objc
        private func handlePlaybackSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard gesture.state == .ended else { return }

            let type: UIPress.PressType = gesture.direction == .up ? .upArrow : .downArrow
            onPressEvent.send(.init(type: type, phase: .ended, defaultAction: {}))
        }

        private func forwardPressesBegan(
            _ presses: Set<UIPress>,
            event: UIPressesEvent?
        ) {
            super.pressesBegan(presses, with: event)
        }

        private func forwardPressesEnded(
            _ presses: Set<UIPress>,
            event: UIPressesEvent?
        ) {
            super.pressesEnded(presses, with: event)
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                let pressType = press.type.normalizedRemoteType
                switch pressType {
                case .playPause, .select:
                    continue
                case .menu:
                    #if DEBUG
                    EpisodePlaybackDiagnostics.logEpisodesBack(
                        manager.episodePlaybackDiagnosticID,
                        event: "menu-pressesBegan episodes=\(containerState.isPresentingPlaybackEpisodes) dropdown=\(containerState.isPresentingPlaybackDropdown) segment=\(manager.screenSegmentCoordinator.presentation != nil)"
                    )
                    #endif
                    continue
                default:
                    let defaultAction: () -> Void = { [weak self] in
                        guard let self else { return }
                        self.forwardPressesBegan([press], event: event)
                    }

                    onPressEvent.send(
                        .init(
                            type: pressType,
                            phase: press.phase,
                            defaultAction: defaultAction
                        )
                    )
                }
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                let pressType = press.type.normalizedRemoteType
                switch pressType {
                case .playPause:
                    handlePlayPauseEnded()
                case .select:
                    handleSelectEnded(press, event: event)
                case .menu:
                    #if DEBUG
                    EpisodePlaybackDiagnostics.logEpisodesBack(
                        manager.episodePlaybackDiagnosticID,
                        event: "menu-pressesEnded episodes=\(containerState.isPresentingPlaybackEpisodes)"
                    )
                    #endif
                    continue
                default:
                    let defaultAction: () -> Void = { [weak self] in
                        guard let self else { return }
                        self.forwardPressesEnded([press], event: event)
                    }

                    onPressEvent.send(
                        .init(
                            type: pressType,
                            phase: press.phase,
                            defaultAction: defaultAction
                        )
                    )
                }
            }
        }

        private func handlePlayPauseEnded() {
            if containerState.isPresentingSegmentOverlay {
                if let presentation = manager.screenSegmentCoordinator.presentation,
                   case .countdown = presentation.kind
                {
                    manager.screenSegmentCoordinator.playNextEpisode()
                }
                return
            }

            if containerState.isPresentingPlaybackDropdown {
                switch manager.playbackRequestStatus {
                case .playing:
                    manager.setPlaybackRequestStatus(status: .paused)
                case .paused:
                    manager.setPlaybackRequestStatus(status: .playing)
                }
                return
            }

            if containerState.isScrubbing {
                containerState.cancelScrub()
                containerState.timer.poke()
                return
            }

            if !containerState.isPresentingOverlay {
                if manager.playbackRequestStatus == .paused {
                    manager.setPlaybackRequestStatus(status: .playing)
                }
                containerState.isPresentingOverlay = true
            } else {
                switch manager.playbackRequestStatus {
                case .playing:
                    manager.setPlaybackRequestStatus(status: .paused)
                case .paused:
                    manager.setPlaybackRequestStatus(status: .playing)
                }
            }

            containerState.timer.poke()
        }

        private func handleSelectEnded(_ press: UIPress, event: UIPressesEvent?) {
            #if os(tvOS) && DEBUG
            PlaybackScrubDiagnostics.log(
                "select-ended scrubbing=\(containerState.isScrubbing) focused=\(containerState.isProgressBarFocused) current=\(manager.seconds) pending=\(containerState.scrubbedSeconds.value)"
            )
            #endif
            if containerState.isPresentingSegmentOverlay {
                forwardPressesEnded([press], event: event)
                return
            }

            if containerState.isPresentingPlaybackDropdown {
                forwardPressesEnded([press], event: event)
                return
            }

            if !containerState.isPresentingOverlay {
                containerState.isPresentingOverlay = true
                containerState.timer.poke()
                return
            }

            if containerState.isScrubbing {
                containerState.commitScrub()
                containerState.timer.poke()
            } else if containerState.isProgressBarFocused {
                switch manager.playbackRequestStatus {
                case .playing:
                    manager.setPlaybackRequestStatus(status: .paused)
                case .paused:
                    manager.setPlaybackRequestStatus(status: .playing)
                }
                containerState.timer.poke()
            } else {
                forwardPressesEnded([press], event: event)
            }
        }

        func handleMenuEnded() {
            #if os(tvOS) && DEBUG
            PlaybackScrubDiagnostics.log(
                "back-ended scrubbing=\(containerState.isScrubbing) focused=\(containerState.isProgressBarFocused) current=\(manager.seconds) pending=\(containerState.scrubbedSeconds.value)"
            )
            #endif
            #if DEBUG
            EpisodePlaybackDiagnostics.logEpisodesBack(
                manager.episodePlaybackDiagnosticID,
                event: "handleMenuEnded-enter episodes=\(containerState.isPresentingPlaybackEpisodes) dropdown=\(containerState.isPresentingPlaybackDropdown) segment=\(manager.screenSegmentCoordinator.presentation != nil) scrubbing=\(containerState.isScrubbing) supplement=\(containerState.isPresentingSupplement) hud=\(containerState.isPresentingOverlay)"
            )
            EpisodePlaybackDiagnostics.log(
                manager.episodePlaybackDiagnosticID,
                event: "back-press dropdown=\(containerState.isPresentingPlaybackDropdown) episodes=\(containerState.isPresentingPlaybackEpisodes) segment=\(manager.screenSegmentCoordinator.presentation != nil) scrubbing=\(containerState.isScrubbing) supplement=\(containerState.isPresentingSupplement) hud=\(containerState.isPresentingOverlay)"
            )
            #endif
            if containerState.closePlaybackDropdownForMenuPress() {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(
                    manager.episodePlaybackDiagnosticID,
                    event: "handleMenuEnded-branch close-dropdown"
                )
                #endif
                releasePlaybackOverlayMenuDismissalGuard()
                return
            } else if containerState.isPresentingPlaybackEpisodes {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(
                    manager.episodePlaybackDiagnosticID,
                    event: "handleMenuEnded-branch close-episodes"
                )
                #endif
                containerState.isPlaybackOverlayMenuDismissalGuarded = true
                containerState.isPresentingPlaybackEpisodes = false
                containerState.isProgressBarFocused = false
                containerState.timer.poke()
                releasePlaybackOverlayMenuDismissalGuard()
                return
            } else if manager.screenSegmentCoordinator.presentation != nil {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(
                    manager.episodePlaybackDiagnosticID,
                    event: "handleMenuEnded-branch segment-back"
                )
                #endif
                containerState.isPlaybackOverlayMenuDismissalGuarded = true
                let consumed = manager.screenSegmentCoordinator.handleMenuBack()
                if consumed, manager.screenSegmentCoordinator.presentation == nil {
                    containerState.isPresentingOverlay = true
                }
                releasePlaybackOverlayMenuDismissalGuard()
                return
            } else if containerState.isScrubbing {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(
                    manager.episodePlaybackDiagnosticID,
                    event: "handleMenuEnded-branch cancel-scrub"
                )
                #endif
                containerState.cancelScrub()
                containerState.timer.poke()
            } else if containerState.isPresentingSupplement {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(
                    manager.episodePlaybackDiagnosticID,
                    event: "handleMenuEnded-branch close-supplement"
                )
                #endif
                containerState.selectedSupplement = nil
                presentSupplementContainer(false)
                containerState.isProgressBarFocused = true
                containerState.timer.poke()
            } else if containerState.isPresentingOverlay {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(manager.episodePlaybackDiagnosticID, event: "handleMenuEnded-branch hide-hud")
                #endif
                containerState.isPresentingOverlay = false
            } else if Defaults[.confirmClose] {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(
                    manager.episodePlaybackDiagnosticID,
                    event: "handleMenuEnded-branch show-close-confirmation"
                )
                EpisodePlaybackDiagnostics.log(
                    manager.episodePlaybackDiagnosticID,
                    event: "back-close-confirmation-presented"
                )
                #endif
                containerState.isPresentingCloseConfirmation = true
            } else {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(manager.episodePlaybackDiagnosticID, event: "handleMenuEnded-branch stop-player")
                EpisodePlaybackDiagnostics.log(
                    manager.episodePlaybackDiagnosticID,
                    event: "back-stop-request"
                )
                #endif
                manager.stop()
            }
        }

        private func releasePlaybackOverlayMenuDismissalGuard() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.containerState.isPlaybackOverlayMenuDismissalGuarded = false
            }
        }
        #endif
    }
}

// MARK: - tvOS PressEvent

#if os(tvOS)
extension VideoPlayer.UIVideoPlayerContainerViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let isPlaybackSwipe = gestureRecognizer is UISwipeGestureRecognizer || otherGestureRecognizer is UISwipeGestureRecognizer
        let horizontalPan = (gestureRecognizer as? DirectionalPanGestureRecognizer) ??
            (otherGestureRecognizer as? DirectionalPanGestureRecognizer)

        if isPlaybackSwipe,
           let horizontalPan,
           horizontalPan.view === view,
           horizontalPan.direction == .horizontal,
           canBeginBackgroundPlaybackScrub || playbackScrubPanStartSeconds != nil
        {
            return true
        }

        guard isPlaybackSwipe,
              let horizontalPan,
              horizontalPan.direction == .horizontal,
              containerState.isPresentingOverlay,
              containerState.isProgressBarFocused,
              !containerState.isScrubbing,
              !containerState.isPresentingSupplement,
              !containerState.isPresentingPlaybackDropdown,
              !containerState.isPresentingPlaybackEpisodes,
              !containerState.isPresentingSegmentOverlay
        else { return false }

        let velocity = horizontalPan.velocity(in: horizontalPan.view)
        let isHorizontalIntent = abs(velocity.x) > abs(velocity.y)
        #if DEBUG
        PlaybackScrubDiagnostics.log(
            "gesture-arbitration horizontalPan=true horizontalIntent=\(isHorizontalIntent) velocityX=\(velocity.x) velocityY=\(velocity.y)"
        )
        #endif
        return isHorizontalIntent
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let horizontalPan = gestureRecognizer as? DirectionalPanGestureRecognizer,
           horizontalPan.view === view,
           horizontalPan.direction == .horizontal
        {
            guard canBeginBackgroundPlaybackScrub else { return false }
            let velocity = horizontalPan.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y)
        }

        guard gestureRecognizer is UISwipeGestureRecognizer else {
            return true
        }

        guard !containerState.isPresentingSegmentOverlay,
              !containerState.isPresentingSupplement,
              !hasPresentedChild(in: self)
        else { return false }

        if containerState.isPresentingPlaybackDropdown {
            if containerState.isPlaybackDropdownTopNavigationFocused {
                return true
            }
            if containerState.playbackDropdownSectionIndex == 0 {
                return true
            }
            return containerState.playbackDropdownSectionIndex == 1 &&
                containerState.isPlaybackDropdownSettingFocused
        }

        return true
    }

    private func hasPresentedChild(in controller: UIViewController) -> Bool {
        controller.presentedViewController != nil || controller.children.contains { hasPresentedChild(in: $0) }
    }
}

extension VideoPlayer.UIVideoPlayerContainerViewController {

    struct PressEvent {

        enum Resolution {
            case handled
            case fallback
        }

        let type: UIPress.PressType
        let phase: UIPress.Phase

        fileprivate let defaultAction: () -> Void

        init(
            type: UIPress.PressType,
            phase: UIPress.Phase,
            defaultAction: @escaping () -> Void
        ) {
            self.type = type.normalizedRemoteType
            self.phase = phase
            self.defaultAction = defaultAction
        }

        func resolve(_ resolution: Resolution) {
            if resolution == .fallback {
                defaultAction()
            }
        }
    }

    typealias OnPressEvent = EventPublisher<PressEvent>
}

private extension UIPress.PressType {

    var normalizedRemoteType: Self {
        // tvOS 27's simulator remote reports these standard remote actions using HID-style raw values.
        switch rawValue {
        case 2079: .rightArrow
        case 2080: .leftArrow
        case 2081: .downArrow
        case 2082: .upArrow
        case 2041: .menu
        default: self
        }
    }
}
#endif

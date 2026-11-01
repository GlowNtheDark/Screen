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
import JellyfinAPI
import SwiftUI
#if DEBUG && os(tvOS)
import os
#endif

#if DEBUG && os(tvOS)
private let sidebarPerformanceLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "com.snowfin.tvos",
    category: "PointsOfInterest"
)

private func sidebarPerformanceEvent(_ name: StaticString, tabID: String) {
    os_signpost(.event, log: sidebarPerformanceLog, name: name, "%{public}s", tabID)
}

private func sidebarPerformanceEvent(_ name: StaticString, tabID: String, latencyMilliseconds: Double) {
    os_signpost(
        .event,
        log: sidebarPerformanceLog,
        name: name,
        "%{public}s latency_ms=%{public}.2f",
        tabID,
        latencyMilliseconds
    )
}

private func sidebarElapsedMilliseconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private final class SidebarPerformanceState {
    var pendingFocusStart: (tabID: String, uptimeNanoseconds: UInt64)?
    var pendingSelectionStart: (tabID: String, uptimeNanoseconds: UInt64)?
}
#endif

// TODO: fix weird tvOS icon rendering
struct MainTabView: View {

    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    @StateObject
    private var tabCoordinator: TabCoordinator

    #if os(tvOS)
    @Namespace
    private var sidebarFocusNamespace

    @Namespace
    private var sidebarSelectionNamespace

    @FocusState
    private var focusedSidebarTabID: String?

    @StateObject
    private var tabContentFocusHandoff = TabContentFocusHandoff()

    @State
    private var previewedSidebarTabID: String?

    #if DEBUG
    @State
    private var sidebarPerformanceState = SidebarPerformanceState()
    #endif

    @State
    private var hasRequestedLaunchContentFocus = false

    @State
    private var isAwaitingLaunchContentFocus = true

    @State
    private var isSidebarPresent = true

    @State
    private var homePlaybackCoordinator: FocusCoordinator?
    @State
    private var protectsHomePlaybackReturn = false
    @State
    private var homeNavigationCoordinator: NavigationCoordinator?
    @State
    private var homeDetailsCoordinator: NavigationCoordinator?
    @State
    private var homeDirectPlayerIsPresented = false
    @State
    private var homeDetailsPlayerIsPresented = false

    @StateObject
    private var searchFocus = TVSearchFocusCoordinator()

    @Environment(\.screenTheme)
    private var screenTheme

    @Default(.sidebarClockEnabled)
    private var sidebarClockEnabled
    #endif

    init() {
        _tabCoordinator = StateObject(wrappedValue: Self.defaultTabCoordinator)
    }

    private static var defaultTabCoordinator: TabCoordinator {
        #if os(iOS)
        TabCoordinator {
            TabItem.contentGroup(provider: DefaultContentGroupProvider())
            TabItem.search
            TabItem.myMedia
            TabItem.requests
        }
        #else
        TabCoordinator {
            TabItem.contentGroup(provider: DefaultContentGroupProvider())
            TabItem.library(
                title: L10n.tvShowsCapitalized,
                systemName: "tv",
                filters: .init(itemTypes: [.series]),
                keepsContentAlive: true,
                observesItemState: true
            )
            TabItem.library(
                title: L10n.movies,
                systemName: "film",
                filters: .init(itemTypes: [.movie]),
                keepsContentAlive: true,
                observesItemState: true
            )
            TabItem.search
            TabItem.requests
            TabItem.settings
        }
        #endif
    }

    private func routePendingDeepLink(_ deepLink: DeepLink?) {
        guard let deepLink else { return }

        Task { @MainActor in
            let route = deepLink.route()
            await tabCoordinator.route(to: route)
        }
    }

    #if os(iOS)
    private func tabContent() -> some View {
        TabView(selection: $tabCoordinator.selectedTabID) {
            ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                Tab(
                    value: tab.item.id,
                    role: tab.item.id == TabItem.search.id ? .search : nil
                ) {
                    NavigationInjectionView(
                        coordinator: tab.coordinator
                    ) {
                        tab.item.content
                            .if(tabCoordinator.tabs.first?.item.id == tab.item.id) { view in
                                view.topBarTrailing {
                                    FirstTabSettingsBarButton()
                                }
                            }
                    }
                    .environmentObject(tabCoordinator)
                    .environment(\.tabItemSelected, tab.publisher)
                } label: {
                    Label(
                        tab.item.displayTitle,
                        systemImage: tab.item.systemImage
                    )
                    .symbolRenderingMode(.monochrome)
                }
            }
        }
    }
    #else
    private var isSidebarExpanded: Bool {
        focusedSidebarTabID != nil && !isSidebarHandoffInProgress
    }

    private var isSidebarHandoffInProgress: Bool {
        tabContentFocusHandoff.pendingTabID != nil
    }

    private var displayedTabID: String? {
        previewedSidebarTabID ?? tabCoordinator.selectedTabID
    }

    private func activateSidebarTab(_ tab: TabCoordinator.TabData, source: String) {
        #if DEBUG
        let selectionStartedAt = DispatchTime.now().uptimeNanoseconds
        sidebarPerformanceState.pendingSelectionStart = (tab.item.id, selectionStartedAt)
        sidebarPerformanceEvent("SidebarSelectionStarted", tabID: tab.item.id)
        LibraryFocusDiagnostics.record(
            "sidebar-activation",
            tabID: tab.item.id,
            detail: "source=\(source) pathIsRoot=\(tab.coordinator.path.isEmpty)"
        )
        #endif
        homePlaybackCoordinator?.cancelHomeReturn()
        let isHome = tab.item.id == tabCoordinator.tabs.first?.item.id
        if isHome {
            homePlaybackCoordinator?.prepareSidebarHomeReturn()
        } else {
            homePlaybackCoordinator?.cancelSidebarHomeReturn()
        }
        let restoresHomeTile = isHome && homePlaybackCoordinator?.isRestoringSidebarHomeFocus == true
        let entersRootContent = tab.coordinator.path.isEmpty
        let requiresFocusHandoff = restoresHomeTile || (
            entersRootContent && (
                tab.item.id == TabItem.search.id ||
                    tab.item.id == TabItem.requests.id ||
                    tab.item.id == "settings" ||
                    tab.item.keepsContentAlive
            )
        )
        tabContentFocusHandoff.begin(tabID: requiresFocusHandoff ? tab.item.id : nil)
        previewedSidebarTabID = tab.item.id
        if tabCoordinator.selectedTabID != tab.item.id {
            tabCoordinator.selectedTabID = tab.item.id
        }
        focusedSidebarTabID = nil
        #if DEBUG
        LibraryFocusDiagnostics.record(
            "sidebar-focus-cleared",
            tabID: tab.item.id,
            detail: "requested state; engine acquisition not implied"
        )
        sidebarPerformanceEvent(
            "SidebarSelectionHandlerReturned",
            tabID: tab.item.id,
            latencyMilliseconds: sidebarElapsedMilliseconds(since: selectionStartedAt)
        )
        #endif
        if restoresHomeTile {
            homePlaybackCoordinator?.sidebarReleasedHomeFocus()
        }

        if tab.item.id == TabItem.search.id, tab.coordinator.path.isEmpty {
            DispatchQueue.main.async {
                guard displayedTabID == tab.item.id else { return }
                #if DEBUG
                sidebarPerformanceEvent("SidebarSelectionEventSent", tabID: tab.item.id)
                #endif
                searchFocus.requestEntry()
            }
            return
        }

        // The exact Home tile request above replaces the generic root-tab
        // request. Sending both would restore the tile, then move focus to the
        // first Home group when the queued root event arrives.
        guard !restoresHomeTile else { return }

        // Let the sidebar relinquish focus before delivering the repeated-tab
        // event that asks the destination to focus its primary content.
        DispatchQueue.main.async {
            guard displayedTabID == tab.item.id else { return }
            #if DEBUG
            sidebarPerformanceEvent("SidebarSelectionEventSent", tabID: tab.item.id)
            LibraryFocusDiagnostics.record(
                "root-tab-event-sent",
                tabID: tab.item.id,
                detail: "isRoot=\(tab.coordinator.path.isEmpty), isRepeat=true"
            )
            #endif
            tab.publisher.send(.init(isRoot: tab.coordinator.path.isEmpty, isRepeat: true))
        }
    }

    private func returnToSidebar(tabID: String) {
        guard tabCoordinator.tabs.contains(where: { $0.item.id == tabID }) else { return }
        focusedSidebarTabID = tabID
    }

    private func requestInitialHomeContentFocus(for tab: TabCoordinator.TabData) {
        guard !hasRequestedLaunchContentFocus,
              tab.item.id == tabCoordinator.tabs.first?.item.id,
              tab.item.id == tabCoordinator.selectedTabID,
              tab.coordinator.path.isEmpty
        else { return }

        hasRequestedLaunchContentFocus = true
        tab.publisher.send(.init(isRoot: true, isRepeat: true))
    }

    private func initialHomeContentFocusAcquired(for tab: TabCoordinator.TabData) {
        guard isAwaitingLaunchContentFocus,
              hasRequestedLaunchContentFocus,
              tab.item.id == tabCoordinator.tabs.first?.item.id,
              tab.item.id == tabCoordinator.selectedTabID,
              tab.coordinator.path.isEmpty
        else { return }

        isAwaitingLaunchContentFocus = false
    }

    @ViewBuilder
    private func selectedTabContent() -> some View {
        ZStack {
            ForEach(
                tabCoordinator.tabs.filter { $0.item.keepsContentAlive || $0.item.id == displayedTabID },
                id: \.item.id
            ) { tab in
                let isActive = tab.item.id == displayedTabID
                let isHomeTab = tab.item.id == tabCoordinator.tabs.first?.item.id
                NavigationInjectionView(
                    coordinator: tab.coordinator
                ) {
                    tab.item.content
                }
                .environmentObject(tabCoordinator)
                .environmentObject(tabContentFocusHandoff)
                .environment(\.tabItemSelected, tab.publisher)
                .environment(\.episodeRouteTabID, tab.item.id)
                .onReceive(
                    tab.coordinator.$presentedSheet
                        .combineLatest(tab.coordinator.$presentedFullScreen)
                ) { presentedSheet, presentedFullScreen in
                    guard isActive else { return }
                    isSidebarPresent = presentedSheet == nil && presentedFullScreen == nil
                }
                .onChange(of: isActive) { _, isActive in
                    guard isActive else { return }
                    isSidebarPresent = tab.coordinator.presentedSheet == nil &&
                        tab.coordinator.presentedFullScreen == nil
                }
                .environment(\.isTabContentFocusable, isActive && !isSidebarExpanded)
                .id(tab.item.id)
                .environment(\.isTabContentActive, tab.item.keepsContentAlive ? isActive : true)
                .opacity(isActive ? 1 : 0)
                .disabled(!isActive || isSidebarExpanded)
                .allowsHitTesting(isActive)
                .accessibilityHidden(!isActive || isSidebarExpanded)
                .environment(\.initialTabCandidateReady, isHomeTab ? {
                    requestInitialHomeContentFocus(for: tab)
                } : nil)
                .environment(\.initialTabCandidateFocused, isHomeTab ? {
                    initialHomeContentFocusAcquired(for: tab)
                } : nil)
                .environment(\.registerHomeFocus, isHomeTab ? { coordinator, navigationCoordinator in
                    let previousCoordinator = homePlaybackCoordinator
                    coordinator.inheritLastFocusedHomeTile(homePlaybackCoordinator?.lastFocusedHomeTile)
                    homePlaybackCoordinator = coordinator
                    homeNavigationCoordinator = navigationCoordinator
                    if focusedSidebarTabID == tab.item.id || previousCoordinator?.isRestoringSidebarHomeFocus == true {
                        coordinator.prepareSidebarHomeReturn()
                    }
                } : nil)
                .onExitCommand {
                    guard isActive, !protectsHomePlaybackReturn else { return }
                    returnToSidebar(tabID: tab.item.id)
                }
            }
        }
    }

    private func sidebarButton(for tab: TabCoordinator.TabData) -> some View {
        let isSelected = tab.item.id == tabCoordinator.selectedTabID
        let isFocused = tab.item.id == focusedSidebarTabID
        let rowForeground = isFocused ? screenTheme.sidebar.focusedForeground.swiftUIColor :
            isSelected ? screenTheme.sidebar.selectedForeground.swiftUIColor : screenTheme.sidebar.idleForeground.swiftUIColor

        return Button {
            activateSidebarTab(tab, source: "select")
        } label: {
            HStack(spacing: 14) {
                Image(systemName: tab.item.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(rowForeground)
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
                    .animation(.easeInOut(duration: 0.2), value: screenTheme)

                if isSidebarExpanded {
                    Text(tab.item.displayTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(rowForeground)
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                        .animation(.easeInOut(duration: 0.2), value: isSelected)
                        .animation(.easeInOut(duration: 0.2), value: screenTheme)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, isSidebarExpanded ? 14 : 11)
            .frame(width: isSidebarExpanded ? nil : 60, alignment: .leading)
            .frame(minHeight: 64, alignment: .leading)
            .frame(maxWidth: isSidebarExpanded ? .infinity : nil, alignment: .leading)
            .background {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(isSelected ? screenTheme.sidebar.selectedBackground.swiftUIColor : .clear)
                        .animation(.easeInOut(duration: 0.2), value: isSelected)
                        .animation(.easeInOut(duration: 0.2), value: screenTheme)

                    Rectangle()
                        .fill(isFocused ? screenTheme.sidebar.focusedBackground.swiftUIColor : .clear)
                        .shadow(
                            color: isFocused ? screenTheme.focus.glow.swiftUIColor.opacity(screenTheme.focus.glowOpacity * 0.45) : .clear,
                            radius: isFocused ? screenTheme.focus.glowRadius * 0.5 : 0
                        )
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                        .animation(.easeInOut(duration: 0.2), value: screenTheme)

                    if isSelected {
                        Rectangle()
                            .fill(screenTheme.sidebar.selectionIndicator.swiftUIColor)
                            .frame(width: 5)
                            .matchedGeometryEffect(id: "selected-page", in: sidebarSelectionNamespace)
                            .animation(.easeInOut(duration: 0.2), value: isSelected)
                            .animation(.easeInOut(duration: 0.2), value: screenTheme)
                    }
                }
            }
            .overlay {
                Rectangle()
                    .strokeBorder(
                        isFocused ? screenTheme.focus.keylineOnSurface.swiftUIColor : .clear,
                        lineWidth: 2
                    )
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
                    .animation(.easeInOut(duration: 0.2), value: screenTheme)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ScreenSidebarButtonStyle())
        .focused($focusedSidebarTabID, equals: tab.item.id)
        .onMoveCommand { direction in
            guard direction == .right else { return }
            activateSidebarTab(tab, source: "right-arrow")
        }
        .prefersDefaultFocus(
            !isAwaitingLaunchContentFocus && isSelected && !isSidebarHandoffInProgress,
            in: sidebarFocusNamespace
        )
        // While content owns focus, admit only the active destination into the
        // collapsed rail's focus search. Once it acquires focus and expands the
        // rail, every item becomes eligible for normal sidebar navigation.
        .disabled(!isSidebarExpanded && !isSelected)
        .accessibilityLabel(tab.item.displayTitle)
        .padding(.horizontal, 8)
    }

    private func tabContent() -> some View {
        ZStack(alignment: .leading) {
            selectedTabContent()
                .padding(.leading, 84)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image("screen-tvOS-mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)

                    if isSidebarExpanded {
                        Text(L10n.applicationBrand)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(height: 66)
                .padding(.horizontal, 14)

                ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                    sidebarButton(for: tab)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 60)
            .padding(.bottom, 30)
            .frame(width: isSidebarExpanded ? 292 : 84)
            .transaction(value: isSidebarExpanded) { transaction in
                transaction.animation = nil
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                Rectangle()
                    .fill(screenTheme.surfaces.canvas.swiftUIColor)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(screenTheme.sidebar.selectionIndicator.swiftUIColor.opacity(0.2))
                            .frame(width: 1)
                    }
            }
            .focusScope(sidebarFocusNamespace)
            .focusSection()
            .disabled(protectsHomePlaybackReturn || isAwaitingLaunchContentFocus || isSidebarHandoffInProgress)
            .clipped()
            // Expand the complete rail, including its background and clipping bounds.
            .ignoresSafeArea(.container, edges: [.horizontal, .vertical])
            .zIndex(1)
            .onChange(of: focusedSidebarTabID) { _, tabID in
                guard let tabID else { return }
                guard tabCoordinator.tabs.contains(where: { $0.item.id == tabID }) else { return }

                if tabID != tabCoordinator.tabs.first?.item.id {
                    homePlaybackCoordinator?.cancelSidebarHomeReturn()
                }

                if tabID == tabCoordinator.tabs.first?.item.id {
                    homePlaybackCoordinator?.prepareSidebarHomeReturn()
                }
                #if DEBUG
                let startedAt = DispatchTime.now().uptimeNanoseconds
                sidebarPerformanceState.pendingFocusStart = (tabID, startedAt)
                sidebarPerformanceEvent("SidebarFocusObserved", tabID: tabID)
                LibraryFocusDiagnostics.record("sidebar-focusstate-observed", tabID: tabID, detail: "focused tab ID changed")
                #endif
                previewedSidebarTabID = tabID
            }
        }
        .background(screenTheme.surfaces.canvas.swiftUIColor)
        .overlay(alignment: .topTrailing) {
            if isSidebarPresent, sidebarClockEnabled {
                SidebarClock()
                    .padding(.top, 24)
                    .padding(.trailing, 36)
            }
        }
        .onReceive(homeNavigationCoordinator?.$presentedSheet.eraseToAnyPublisher() ?? Just(nil).eraseToAnyPublisher()) { presentedRoute in
            let previousDetailsCoordinator = homeDetailsCoordinator
            homeDetailsCoordinator = presentedRoute?.route.id.hasPrefix("item-") == true ? presentedRoute?.coordinator : nil

            if presentedRoute == nil, previousDetailsCoordinator != nil {
                homePlaybackCoordinator?.homeDetailsDismissed()
            }
        }
        .onReceive(
            homeNavigationCoordinator?.$presentedFullScreen.eraseToAnyPublisher() ??
                Just(nil).eraseToAnyPublisher()
        ) { presentedRoute in
            if presentedRoute?.route.id == "videoPlayer" {
                homeDirectPlayerIsPresented = true
                homePlaybackCoordinator?.homePlayerPresented(fromDetails: false)
            } else if homeDirectPlayerIsPresented {
                homeDirectPlayerIsPresented = false
                homePlaybackCoordinator?.homePlayerDismissed()
            }
        }
        .onReceive(
            homeDetailsCoordinator?.$presentedFullScreen.eraseToAnyPublisher() ??
                Just(nil).eraseToAnyPublisher()
        ) { presentedRoute in
            if presentedRoute?.route.id == "videoPlayer" {
                homeDetailsPlayerIsPresented = true
                homePlaybackCoordinator?.homePlayerPresented(fromDetails: true)
            } else if homeDetailsPlayerIsPresented {
                homeDetailsPlayerIsPresented = false
                homePlaybackCoordinator?.homePlayerDismissed()
            }
        }
        .onReceive(
            homePlaybackCoordinator?.$protectsHomeReturn.eraseToAnyPublisher() ??
                Just(false).eraseToAnyPublisher()
        ) { protecting in
            protectsHomePlaybackReturn = protecting
            if protecting {
                focusedSidebarTabID = nil
            }
        }
        .onReceive(
            homePlaybackCoordinator?.$isRestoringSidebarHomeFocus.eraseToAnyPublisher() ??
                Just(false).eraseToAnyPublisher()
        ) { restoring in
            if !restoring,
               let homeTabID = tabCoordinator.tabs.first?.item.id,
               tabContentFocusHandoff.pendingTabID == homeTabID
            {
                tabContentFocusHandoff.complete(tabID: homeTabID)
            }
        }
        .onChange(of: tabCoordinator.selectedTabID) { _, tabID in
            if tabID != tabCoordinator.tabs.first?.item.id {
                isAwaitingLaunchContentFocus = false
            }
            guard focusedSidebarTabID == nil else { return }
            previewedSidebarTabID = tabID
        }
        #if DEBUG
        .onChange(of: displayedTabID) { _, tabID in
                guard let tabID else { return }
                sidebarPerformanceEvent("SidebarPreviewActivated", tabID: tabID)
                LibraryFocusDiagnostics.record(
                    "displayed-tab-changed",
                    tabID: tabID,
                    detail: "selected=\(tabCoordinator.selectedTabID ?? "-") sidebarExpanded=\(isSidebarExpanded)"
                )
                if let pendingSidebarFocusStart = sidebarPerformanceState.pendingFocusStart,
                   pendingSidebarFocusStart.tabID == tabID
                {
                    sidebarPerformanceEvent(
                        "SidebarFocusToPreview",
                        tabID: tabID,
                        latencyMilliseconds: sidebarElapsedMilliseconds(since: pendingSidebarFocusStart.uptimeNanoseconds)
                    )
                    sidebarPerformanceState.pendingFocusStart = nil
                }
                if let pendingSidebarSelectionStart = sidebarPerformanceState.pendingSelectionStart,
                   pendingSidebarSelectionStart.tabID == tabID
                {
                    sidebarPerformanceEvent(
                        "SidebarSelectionToPreview",
                        tabID: tabID,
                        latencyMilliseconds: sidebarElapsedMilliseconds(since: pendingSidebarSelectionStart.uptimeNanoseconds)
                    )
                    sidebarPerformanceState.pendingSelectionStart = nil
                }
            }
        #endif
    }
    #endif

    var body: some View {
        tabContent()
            .onChange(of: userSessionManager.pendingDeepLink) {
                routePendingDeepLink(userSessionManager.consumePendingDeepLink())
            }
            .onReceive(userSessionManager.routePublisher) { route in
                Task { @MainActor in
                    await tabCoordinator.route(to: route)
                }
            }
        #if os(tvOS)
            .environmentObject(searchFocus)
            .background(alignment: .top) {
                FocusedPosterCinematicBackgroundView()
            }
        #endif
    }
}

#if os(tvOS)
extension EnvironmentValues {
    @Entry
    var initialTabCandidateReady: (() -> Void)? = nil
    @Entry
    var initialTabCandidateFocused: (() -> Void)? = nil
}

private struct ScreenSidebarButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#endif

#if os(iOS)
private struct FirstTabSettingsBarButton: View {

    @Injected(\.currentUserSession)
    private var userSession

    @Router
    private var router

    var body: some View {
        if router.isRootOfPath,
           let userSession
        {
            SettingsBarButton(
                server: userSession.server,
                user: userSession.user
            ) {
                router.route(to: .settings)
            }
        }
    }
}
#endif

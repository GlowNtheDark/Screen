//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension VideoPlayer.PlaybackControls {

    struct Dropdown: View {

        private enum Section: String, CaseIterable, Hashable {
            case info
            case playbackSettings
            case technicalDetails

            var title: String {
                switch self {
                case .info:
                    L10n.info
                case .playbackSettings:
                    // swiftlint:disable:next hard_coded_display_string
                    "Playback Settings"
                case .technicalDetails:
                    // swiftlint:disable:next hard_coded_display_string
                    "Technical Details"
                }
            }
        }

        private enum Setting: CaseIterable, Hashable {
            case quality
            case audio
            case subtitles

            var index: Int {
                Self.allCases.firstIndex(of: self) ?? 0
            }
        }

        private enum FocusTarget: Hashable {
            case section(Section)
            case setting(Setting)
        }

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        @Environment(\.screenTheme)
        private var screenTheme

        @FocusState
        private var focusedTarget: FocusTarget?

        @FocusState
        private var focusedRestartAction: Bool

        @Namespace
        private var focusScope

        @State
        private var selectedSection: Section = .info
        @State
        private var fallbackPlaybackInformation: PlaybackInformationSupplement?

        private var currentItemID: String {
            manager.item.id ?? "any"
        }

        private var mediaInfoSupplement: MediaInfoSupplement {
            let id = "MediaInfo-\(currentItemID)"
            let supplement = manager.supplements.first(where: { $0.id == id }) as? MediaInfoSupplement
            return supplement ?? MediaInfoSupplement(item: manager.item)
        }

        private var playbackInformationSupplement: PlaybackInformationSupplement? {
            let id = "PlaybackInformation-\(currentItemID)"
            return (manager.supplements.first(where: { $0.id == id }) as? PlaybackInformationSupplement)
                ?? fallbackPlaybackInformation
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 26) {
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Text(manager.item.displayTitle)
                                .font(.title2.weight(.semibold))
                                .lineLimit(1)

                            Spacer(minLength: 20)

                            // swiftlint:disable:next hard_coded_display_string
                            Label("Up or Back to close", systemImage: "chevron.up")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 16) {
                            ForEach(Section.allCases, id: \.self) { section in
                                sectionButton(section)
                            }
                        }
                        .focusSection()

                        Rectangle()
                            .fill(screenTheme.actions.secondaryBoundary.swiftUIColor.opacity(0.72))
                            .frame(height: 1)

                        sectionContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .padding(42)
                    .frame(
                        width: min(geometry.size.width * 0.92, 1680),
                        height: min(geometry.size.height * 0.78, 850),
                        alignment: .topLeading
                    )
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Rectangle()
                                    .fill(screenTheme.surfaces.canvas.swiftUIColor.opacity(0.78))
                            }
                    }
                    .overlay {
                        Rectangle()
                            .stroke(screenTheme.actions.secondaryBoundary.swiftUIColor.opacity(0.72), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.46), radius: 34, x: 0, y: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .focusScope(focusScope)
            .focusSection()
            .defaultFocus($focusedTarget, .section(.info), priority: .userInitiated)
            .onAppear {
                focusedTarget = .section(.info)
                focusedRestartAction = false
                containerState.playbackDropdownSectionIndex = 0
                containerState.playbackDropdownFocusRequest = .section(0)
                containerState.isPlaybackDropdownTopNavigationFocused = true
            }
            .onChange(of: focusedTarget) {
                if case .setting = focusedTarget {
                    containerState.isPlaybackDropdownSettingFocused = true
                } else {
                    containerState.isPlaybackDropdownSettingFocused = false
                }

                guard let focusedTarget else {
                    containerState.isPlaybackDropdownTopNavigationFocused = false
                    return
                }

                switch focusedTarget {
                case let .section(section):
                    focusedRestartAction = false
                    let index = Section.allCases.firstIndex(of: section) ?? 0
                    containerState.isPlaybackDropdownTopNavigationFocused = true
                    containerState.playbackDropdownSectionIndex = index
                    containerState.playbackDropdownFocusRequest = .section(index)

                case let .setting(setting):
                    focusedRestartAction = false
                    containerState.isPlaybackDropdownTopNavigationFocused = false
                    containerState.playbackDropdownSettingIndex = setting.index
                    containerState.playbackDropdownFocusRequest = .setting(setting.index)
                }
            }
            .onDisappear {
                containerState.isPlaybackDropdownSettingFocused = false
            }
            .onChange(of: containerState.playbackDropdownSectionIndex) { _, index in
                guard Section.allCases.indices.contains(index) else { return }
                let section = Section.allCases[index]
                selectedSection = section
                focusedTarget = .section(section)
                containerState.isPlaybackDropdownTopNavigationFocused = true
            }
            .onChange(of: containerState.playbackDropdownFocusRequest) { _, request in
                guard let request else { return }
                switch request {
                case let .section(index) where Section.allCases.indices.contains(index):
                    let section = Section.allCases[index]
                    focusedRestartAction = false
                    selectedSection = section
                    focusedTarget = .section(section)
                    containerState.isPlaybackDropdownTopNavigationFocused = true

                case let .setting(index) where Setting.allCases.indices.contains(index):
                    focusedRestartAction = false
                    focusedTarget = .setting(Setting.allCases[index])
                    containerState.isPlaybackDropdownTopNavigationFocused = false

                case .restartEpisode:
                    selectedSection = .info
                    focusedTarget = nil
                    focusedRestartAction = true
                    containerState.playbackDropdownSectionIndex = 0
                    containerState.isPlaybackDropdownTopNavigationFocused = false

                case .technicalDetailsFirstRow:
                    selectedSection = .technicalDetails
                    focusedTarget = nil
                    containerState.isPlaybackDropdownTopNavigationFocused = false

                default:
                    break
                }
            }
            .onMoveCommand { direction in
                switch direction {
                case .down where containerState.isPlaybackDropdownTopNavigationFocused && selectedSection == .info:
                    containerState.isPlaybackDropdownTopNavigationFocused = false
                    containerState.playbackDropdownFocusRequest = .restartEpisode

                case .up where focusedRestartAction:
                    containerState.playbackDropdownFocusRequest = .section(0)

                case .up where containerState.isPlaybackDropdownTopNavigationFocused:
                    containerState.isPresentingPlaybackDropdown = false

                case .up where containerState.playbackDropdownSectionIndex == 1:
                    containerState.playbackDropdownFocusRequest = .section(containerState.playbackDropdownSectionIndex)

                case .down where containerState.isPlaybackDropdownTopNavigationFocused && selectedSection == .technicalDetails:
                    containerState.isPlaybackDropdownTopNavigationFocused = false
                    containerState.playbackDropdownFocusRequest = .technicalDetailsFirstRow

                default:
                    break
                }
            }
            .task(id: manager.item.id) {
                guard manager.item.id != nil,
                      playbackInformationSupplement == nil
                else { return }
                fallbackPlaybackInformation = PlaybackInformationSupplement(itemID: currentItemID)
            }
        }

        private func sectionButton(_ section: Section) -> some View {
            Button {
                selectedSection = section
                focusedRestartAction = false
                let index = Section.allCases.firstIndex(of: section) ?? 0
                containerState.playbackDropdownSectionIndex = index
                containerState.playbackDropdownFocusRequest = .section(index)
            } label: {
                Text(section.title)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DropdownSectionButtonStyle(isSelected: selectedSection == section))
            .focused($focusedTarget, equals: .section(section))
        }

        @ViewBuilder
        private var sectionContent: some View {
            switch selectedSection {
            case .info:
                mediaInfoSupplement.videoPlayerBody(focusedRestartAction: $focusedRestartAction) {
                    containerState.isPresentingPlaybackDropdown = false
                }
                .eraseToAnyView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            case .playbackSettings:
                playbackSettingsContent

            case .technicalDetails:
                technicalDetailsContent
            }
        }

        @ViewBuilder
        private var playbackSettingsContent: some View {
            HStack(alignment: .top, spacing: 26) {
                settingCard(setting: .quality) {
                    VideoPlayer.PlaybackControls.Toolbar.ActionButtons.PlaybackSettings(showsCurrentSelection: true)
                }

                settingCard(setting: .audio) {
                    VideoPlayer.PlaybackControls.Toolbar.ActionButtons.Audio(showsCurrentSelection: true)
                }

                settingCard(setting: .subtitles) {
                    VideoPlayer.PlaybackControls.Toolbar.ActionButtons.Subtitles(showsCurrentSelection: true)
                }
            }
        }

        private func settingCard(
            setting: Setting,
            @ViewBuilder content: () -> some View
        ) -> some View {
            VStack(alignment: .leading) {
                content()
                    .focused($focusedTarget, equals: .setting(setting))
                    .frame(minHeight: 72, alignment: .leading)
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
            .background(screenTheme.surfaces.canvas.swiftUIColor.opacity(0.24))
            .overlay {
                Rectangle()
                    .stroke(screenTheme.actions.secondaryBoundary.swiftUIColor.opacity(0.58), lineWidth: 1)
            }
        }

        @ViewBuilder
        private var technicalDetailsContent: some View {
            if manager.playbackItem != nil,
               let playbackInformationSupplement
            {
                VStack(alignment: .leading, spacing: 18) {
                    AnyMediaPlayerSupplement(playbackInformationSupplement)
                        .videoPlayerBody
                        .eraseToAnyView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .labeledContentStyle(.playbackInfo)
                .focusSection()
            } else {
                // swiftlint:disable:next hard_coded_display_string
                Text("Playback details are not currently available.")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
    }
}

private struct DropdownSectionButtonStyle: ButtonStyle {

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.screenTheme)
    private var screenTheme

    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fillColor = isSelected
            ? screenTheme.actions.primaryFill.swiftUIColor
            : screenTheme.surfaces.elevatedHigh.swiftUIColor
        let foregroundColor = isSelected
            ? screenTheme.actions.primaryForeground.swiftUIColor
            : screenTheme.foregrounds.primary.swiftUIColor
        let keylineColor = isFocused
            ? isSelected
            ? screenTheme.focus.keylineOnPrimaryFill.swiftUIColor
            : screenTheme.focus.keylineOnSurface.swiftUIColor
            : isSelected
            ? screenTheme.selection.indicator.swiftUIColor
            : screenTheme.actions.secondaryBoundary.swiftUIColor

        return configuration.label
            .foregroundStyle(foregroundColor)
            .background {
                Rectangle()
                    .fill(fillColor)
                    .overlay {
                        Rectangle()
                            .stroke(keylineColor, lineWidth: isFocused ? 3 : 1)
                    }
            }
            .shadow(
                color: isFocused
                    ? screenTheme.focus.glow.swiftUIColor.opacity(screenTheme.focus.glowOpacity)
                    : .clear,
                radius: isFocused ? screenTheme.focus.glowRadius : 0
            )
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.025 : 1))
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: refine segment animations when swiping fast

struct VideoPlayerSlider<Value: BinaryFloatingPoint>: View {

    @Binding
    private var value: Value

    private let total: Value
    private let isScrollingEnabled: Bool
    private var onEditingChanged: (Bool) -> Void

    init(
        value: Binding<Value>,
        total: Value,
        isScrollingEnabled: Bool = true
    ) {
        self._value = value
        self.total = total
        self.isScrollingEnabled = isScrollingEnabled
        self.onEditingChanged = { _ in }
    }

    var body: some View {
        SliderContainer(
            value: $value,
            total: total,
            isScrollingEnabled: isScrollingEnabled,
            decelerates: false,
            onEditingChanged: onEditingChanged
        ) {
            VideoPlayerSliderContent()
        }
    }
}

extension VideoPlayerSlider {

    func onEditingChanged(_ action: @escaping (Bool) -> Void) -> Self {
        copy(modifying: \.onEditingChanged, with: action)
    }
}

private struct VideoPlayerSliderContent: SliderContentView {

    @Environment(\.isEnabled)
    private var isEnabled

    @Environment(\.screenTheme)
    private var screenTheme

    @EnvironmentObject
    private var containerState: VideoPlayerContainerState
    @EnvironmentObject
    var sliderState: SliderContainerState<Double>

    private let tickWidth: CGFloat = 8

    private var activeColor: Color {
        isEnabled ? screenTheme.player.progress.swiftUIColor : screenTheme.foregrounds.disabled.swiftUIColor
    }

    private var scrubbedProgress: Double {
        progress(for: sliderState.value)
    }

    private var visibleTickProgress: Double {
        scrubbedProgress
    }

    private func progress(for value: Double) -> Double {
        guard sliderState.total.isFinite,
              sliderState.total > 0,
              value.isFinite
        else {
            return 0
        }

        return clamp(value / sliderState.total, min: 0, max: 1)
    }

    @ViewBuilder
    private func progressSegment(progress: Double, in size: CGSize) -> some View {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let segmentWidth = max(0, width * progress + height)

        Rectangle()
            .frame(width: segmentWidth)
            .offset(x: -height)
    }

    private func tickOffset(for progress: Double, in width: CGFloat) -> CGFloat {
        guard progress.isFinite, width.isFinite, width > 0 else { return 0 }
        // The leading-aligned stack places this tick's center at the normalized track position.
        return width * progress - tickWidth / 2
    }

    var body: some View {
        GeometryReader { proxy in
            let trackHeight: CGFloat = sliderState.isFocused ? 10 : 8
            let trackSize = CGSize(width: proxy.size.width, height: trackHeight)

            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.22))

                    progressSegment(progress: scrubbedProgress, in: trackSize)
                        .foregroundStyle(activeColor)
                }
                .frame(height: trackHeight)
                .clipShape(Rectangle())

                Rectangle()
                    .fill(activeColor)
                    .frame(width: tickWidth, height: max(trackHeight, proxy.size.height - 2))
                    .overlay {
                        Rectangle()
                            .stroke(screenTheme.focus.keylineOnSurface.swiftUIColor, lineWidth: 1)
                    }
                    .offset(x: tickOffset(for: visibleTickProgress, in: proxy.size.width))
            }
            .clipShape(Rectangle())
        }
        .onChange(of: sliderState.isFocused) {
            if !sliderState.isFocused {
                containerState.cancelScrub()
            }
        }
        .opacity(sliderState.isFocused ? 1 : 0.94)
        .animation(.linear(duration: 0.1), value: sliderState.value)
        .animation(.easeInOut(duration: 0.2), value: sliderState.isFocused)
    }
}

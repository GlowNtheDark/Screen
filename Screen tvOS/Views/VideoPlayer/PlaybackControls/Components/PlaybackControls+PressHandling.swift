//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    func handlePressEvent(_ press: VideoPlayer.UIVideoPlayerContainerViewController.PressEvent) {

        if containerState.isPresentingOverlay,
           !containerState.isScrubbing,
           !containerState.isPresentingSupplement,
           !containerState.isPresentingPlaybackDropdown,
           !containerState.isPresentingPlaybackEpisodes,
           !containerState.isPresentingSegmentOverlay
        {
            containerState.timer.poke()
        }

        if containerState.isPresentingSegmentOverlay {
            press.resolve(.fallback)
            return
        }

        if containerState.isPresentingPlaybackDropdown {
            if containerState.isPlaybackDropdownTopNavigationFocused {
                switch press.type {
                case .upArrow:
                    if press.phase == .ended {
                        containerState.isPresentingPlaybackDropdown = false
                    }
                    press.resolve(.handled)

                case .leftArrow, .rightArrow:
                    if press.phase == .ended {
                        let delta = press.type == .leftArrow ? -1 : 1
                        let sectionCount = 3
                        let nextIndex = (containerState.playbackDropdownSectionIndex + delta + sectionCount) % sectionCount
                        containerState.playbackDropdownSectionIndex = nextIndex
                        containerState.playbackDropdownFocusRequest = .section(nextIndex)
                    }
                    press.resolve(.handled)

                case .downArrow where containerState.playbackDropdownSectionIndex == 1:
                    if press.phase == .ended {
                        containerState.isPlaybackDropdownTopNavigationFocused = false
                        containerState.playbackDropdownFocusRequest = .setting(0)
                    }
                    press.resolve(.handled)

                case .downArrow where containerState.playbackDropdownSectionIndex == 0:
                    if press.phase == .ended {
                        containerState.isPlaybackDropdownTopNavigationFocused = false
                        containerState.playbackDropdownFocusRequest = .restartEpisode
                    }
                    press.resolve(.handled)

                case .downArrow where containerState.playbackDropdownSectionIndex == 2:
                    if press.phase == .ended {
                        containerState.isPlaybackDropdownTopNavigationFocused = false
                        containerState.playbackDropdownFocusRequest = .technicalDetailsFirstRow
                    }
                    press.resolve(.handled)

                default:
                    press.resolve(.fallback)
                }
            } else {
                if containerState.playbackDropdownSectionIndex == 1 {
                    switch press.type {
                    case .upArrow:
                        if press.phase == .ended {
                            containerState.playbackDropdownFocusRequest = .section(containerState.playbackDropdownSectionIndex)
                        }
                        press.resolve(.handled)

                    case .leftArrow, .rightArrow:
                        if press.phase == .ended {
                            let delta = press.type == .leftArrow ? -1 : 1
                            let settingCount = 3
                            let nextIndex = (containerState.playbackDropdownSettingIndex + delta + settingCount) % settingCount
                            containerState.playbackDropdownSettingIndex = nextIndex
                            containerState.playbackDropdownFocusRequest = .setting(nextIndex)
                        }
                        press.resolve(.handled)

                    default:
                        press.resolve(.fallback)
                    }
                } else if containerState.playbackDropdownSectionIndex == 0 {
                    switch press.type {
                    case .upArrow:
                        if press.phase == .ended {
                            containerState.playbackDropdownFocusRequest = .section(0)
                        }
                        press.resolve(.handled)

                    default:
                        press.resolve(.fallback)
                    }
                } else {
                    press.resolve(.fallback)
                }
            }
            return
        }

        if containerState.isPresentingPlaybackEpisodes {
            let direction: PlaybackEpisodesMoveRequest.Direction? = switch press.type {
            case .upArrow:
                .up
            case .downArrow:
                .down
            default:
                nil
            }

            if let direction {
                if press.phase == .ended {
                    containerState.playbackEpisodesMoveRequest = .init(direction)
                }
                press.resolve(.handled)
            } else {
                press.resolve(.fallback)
            }
            return
        }

        if press.type == .upArrow {
            guard containerState.isPresentingOverlay else {
                if press.phase == .ended {
                    containerState.isPresentingOverlay = true
                }
                press.resolve(.handled)
                return
            }

            let canPresentEpisodes = containerState.isPresentingOverlay &&
                !containerState.isPresentingSupplement &&
                manager.queue?.episodeQueue != nil

            guard canPresentEpisodes else {
                press.resolve(.fallback)
                return
            }

            if press.phase == .ended {
                presentEpisodesSurface()
            }
            press.resolve(.handled)
            return
        }

        if press.type == .downArrow {
            if press.phase == .ended {
                if containerState.isScrubbing {
                    containerState.cancelScrub()
                }
                if containerState.isPresentingSupplement {
                    containerState.select(supplement: nil)
                }
                containerState.isPresentingPlaybackDropdown = true
            }
            press.resolve(.handled)
            return
        }

        if !containerState.isPresentingOverlay {
            containerState.isPresentingOverlay = true
            press.resolve(.handled)
            return
        }

        if containerState.isProgressBarFocused {
            switch press.type {
            case .leftArrow, .rightArrow:
                if press.phase == .ended {
                    adjustProgressSeek(forward: press.type == .rightArrow)
                    containerState.timer.poke()
                }
                press.resolve(.handled)
                return
            default:
                break
            }
        }

        containerState.timer.poke()
        press.resolve(.fallback)
    }
}

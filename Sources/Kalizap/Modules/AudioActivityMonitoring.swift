import Foundation

/// Reports whether the system's default audio output device is currently in use
/// by any process, or was in use within a short warmth window. Serves as a
/// proxy for "audio subsystem warm": if it's warm, CoreAudio's output path is
/// active and playback will start immediately; if cold, the first play call
/// may pay a 300–1500ms cold-start.
///
/// Concrete implementations observe CoreAudio state transitions (not just
/// snapshots) so that the brief period after YouTube/Spotify stopped is
/// still treated as warm — the HAL-Lag alone is shorter than ~1s in practice.
///
/// See docs/audio-cold-start/ for the full analysis and decision rationale.
public protocol AudioActivityMonitoring: Sendable {
    func isAudioWarm() -> Bool
}

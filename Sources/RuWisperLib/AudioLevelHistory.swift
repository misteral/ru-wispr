import Foundation

/// Rolling buffer of audio levels for waveform visualization.
/// Left = oldest samples, right = most recent.
///
/// Usage:
///   let history = AudioLevelHistory(capacity: 64)
///   history.push(rawRMS)           // called from audio callback
///   history.levels                  // [Float] for WaveformCanvas
///   history.currentLevel            // smoothed level for RecordingIndicator
@Observable
final class AudioLevelHistory {
    /// Number of bars in the waveform display
    let capacity: Int

    /// Smoothed current audio level (for recording indicator pulsation)
    private(set) var currentLevel: Float = 0

    /// Rolling history: left = oldest, right = newest
    private(set) var levels: [Float]

    private var smoothed: Float = 0

    /// Smoothing factor: 0 = no smoothing (raw), 1 = frozen. Default 0.35 feels responsive.
    var smoothingFactor: Float = 0.35

    init(capacity: Int = 64) {
        self.capacity = capacity
        self.levels = Array(repeating: 0, count: capacity)
    }

    /// Push a raw RMS audio level. Applies smoothing, updates history.
    func push(_ rawLevel: Float) {
        smoothed = smoothed * smoothingFactor + rawLevel * (1 - smoothingFactor)
        currentLevel = smoothed

        levels.append(smoothed)
        if levels.count > capacity {
            levels.removeFirst(levels.count - capacity)
        }
    }

    /// Reset everything (call on recording start)
    func reset() {
        smoothed = 0
        currentLevel = 0
        levels = Array(repeating: 0, count: capacity)
    }
}

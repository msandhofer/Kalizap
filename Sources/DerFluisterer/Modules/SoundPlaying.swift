import Foundation

public protocol SoundPlaying: Sendable {
    func playStartSound() async
    func playStopSound() async
}

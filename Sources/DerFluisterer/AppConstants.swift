import Foundation

public enum AppConstants {
    public static let defaultLLMTimeoutMs: Int = 800

    /// Extra recording duration kept after keyup so a hastily released hotkey
    /// doesn't truncate the user's last word. The recorder runs this long past
    /// the stop event before being torn down; the stop sound and overlay hide
    /// immediately so the user still has instant feedback that stop was seen.
    public static let recordingTailDuration: Duration = .milliseconds(500)
}

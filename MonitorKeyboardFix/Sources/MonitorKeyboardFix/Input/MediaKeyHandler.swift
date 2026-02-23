import Foundation

/// Types of media key actions this app handles.
enum MediaKeyAction {
    case brightnessUp
    case brightnessDown
    case volumeUp
    case volumeDown
    case mute
}

/// Protocol for objects that respond to media key events.
protocol MediaKeyDelegate: AnyObject {
    func handleMediaKey(_ action: MediaKeyAction)
}

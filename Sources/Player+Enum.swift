//
//  Player+Enum.swift
//
//  (\(\
//  ( -.-)
//  o_(")(")
//  -----------------------
//  Created by jeffy on 7/15/25.
//

// MARK: - error types

/// Error domain for all Player errors.
public let PlayerErrorDomain = "PlayerErrorDomain"

/// Error types.
public enum PlayerError: Error, CustomStringConvertible {
    case failed
    
    public var description: String {
        switch self {
        case .failed:
            return "failed"
        }
    }
}

extension Player {
    
    /// Asset playback states.
    public enum PlaybackState: Int, CustomStringConvertible {
        case stopped = 0
        case playing
        case paused
        case failed
        
        public var description: String {
            switch self {
            case .stopped:
                return "Stopped"
            case .playing:
                return "Playing"
            case .failed:
                return "Failed"
            case .paused:
                return "Paused"
            }
        }
    }
    
    /// Asset buffering states.
    public enum BufferingState: Int, CustomStringConvertible {
        case unknown = 0
        case ready
        case delayed
        
        public var description: String {
            switch self {
            case .unknown:
                return "Unknown"
            case .ready:
                return "Ready"
            case .delayed:
                return "Delayed"
            }
        }
    }
    
}

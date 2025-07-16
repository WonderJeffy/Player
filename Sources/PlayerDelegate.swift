//
//  PlayerDelegate.swift
//
//  (\(\
//  ( -.-)
//  o_(")(")
//  -----------------------
//  Created by jeffy on 7/15/25.
//

// MARK: - PlayerDelegate

/// Player delegate protocol
public protocol PlayerDelegate: AnyObject {
    func playerReady(_ player: Player)
    func playerPlaybackStateDidChange(_ player: Player)
    func playerBufferingStateDidChange(_ player: Player)
    
    // This is the time in seconds that the video has been buffered.
    // If implementing a UIProgressView, user this value / player.maximumDuration to set progress.
    func playerBufferTimeDidChange(_ bufferTime: Double)
    
    func player(_ player: Player, didFailWithError error: Error?)
}

/// Player playback protocol
public protocol PlayerPlaybackDelegate: AnyObject {
    func playerCurrentTimeDidChange(_ player: Player)
    func playerPlaybackWillStartFromBeginning(_ player: Player)
    func playerPlaybackDidEnd(_ player: Player)
    func playerPlaybackWillLoop(_ player: Player)
    func playerPlaybackDidLoop(_ player: Player)
}

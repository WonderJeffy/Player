//  Player.swift
//
//  Created by patrick piemonte on 11/26/14.
//
//  The MIT License (MIT)
//
//  Copyright (c) 2014-present patrick piemonte (http://patrickpiemonte.com/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import AVFoundation
import CoreGraphics
import Foundation
import UIKit

// MARK: - Player

/// ▶️ Player, simple way to play and stream media
open class Player: UIViewController {
    
    /// Video fill mode options for `Player.fillMode`.
    ///
    /// - resize: Stretch to fill.
    /// - resizeAspectFill: Preserve aspect ratio, filling bounds.
    /// - resizeAspectFit: Preserve aspect ratio, fill within bounds.
    public typealias FillMode = AVLayerVideoGravity
    
    /// Player delegate.
    open weak var playerDelegate: PlayerDelegate?
    
    /// Playback delegate.
    open weak var playbackDelegate: PlayerPlaybackDelegate?
    
    // configuration
    
    /// Local or remote URL for the file asset to be played.
    ///
    /// - Parameter url: URL of the asset.
    open var url: URL? {
        didSet {
            if let url = self.url {
                setup(url: url)
            }
        }
    }
    
    /// For setting up with AVAsset instead of URL
    /// Note: This will reset the `url` property. (cannot set both)
    open var asset: AVAsset? {
        get { return _asset }
        set { _ = newValue.map { setupAsset($0) } }
    }
    
    /// Specifies how the video is displayed within a player layer’s bounds.
    /// The default value is `AVLayerVideoGravityResizeAspect`. See `PlayerFillMode`.
    open var fillMode: Player.FillMode {
        get {
            return self._playerView.playerFillMode
        }
        set {
            self._playerView.playerFillMode = newValue
        }
    }
    
    /// Determines if the video should autoplay when streaming a URL.
    open var autoplay: Bool = true
    
    /// Mutes audio playback when true.
    open var muted: Bool {
        get {
            return self._avplayer.isMuted
        }
        set {
            self._avplayer.isMuted = newValue
        }
    }
    
    /// Volume for the player, ranging from 0.0 to 1.0 on a linear scale.
    open var volume: Float {
        get {
            return self._avplayer.volume
        }
        set {
            self._avplayer.volume = newValue
        }
    }
    
    /// Rate at which the video should play once it loads
    open var rate: Float = 1 {
        didSet {
            self._avplayer.rate = rate
        }
    }
    
    /// Pauses playback automatically when resigning active.
    open var playbackPausesWhenResigningActive: Bool = true
    
    /// Pauses playback automatically when backgrounded.
    open var playbackPausesWhenBackgrounded: Bool = true
    
    /// Resumes playback when became active.
    open var playbackResumesWhenBecameActive: Bool = true
    
    /// Resumes playback when entering foreground.
    open var playbackResumesWhenEnteringForeground: Bool = true
    
    // MARK: Async State
    
    public func hasVideoTrack() async -> Bool {
        guard let asset = self._asset else {
            return false
        }
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            return !videoTracks.isEmpty
        } catch {
            return false
        }
    }
    
    /// The natural dimensions of the media.
    open var naturalSize: CGSize {
        get async {
            guard let asset = self._asset else {
                return CGSize.zero
            }
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    return CGSize.zero
                }
                let size = try await track.load(.naturalSize).applying(track.load(.preferredTransform))
                return CGSize(width: abs(size.width), height: abs(size.height))
            } catch {
                return CGSize.zero
            }
        }
    }
    
    // MARK: - Sync state
    
    /// Playback automatically loops continuously when true.
    open var playbackLoops: Bool {
        get {
            return self._avplayer.actionAtItemEnd == .none
        }
        set {
            if newValue {
                self._avplayer.actionAtItemEnd = .none
            } else {
                self._avplayer.actionAtItemEnd = .pause
            }
        }
    }
    
    /// Playback freezes on last frame frame when true and does not reset seek position timestamp..
    open var playbackFreezesAtEnd: Bool = false
    
    /// Current playback state of the Player.
    open var playbackState: PlaybackState = .stopped {
        didSet {
            if playbackState != oldValue || !playbackEdgeTriggered {
                self.executeClosureOnMainQueueIfNecessary {
                    self.playerDelegate?.playerPlaybackStateDidChange(self)
                }
            }
        }
    }
    
    /// Current buffering state of the Player.
    open var bufferingState: BufferingState = .unknown {
        didSet {
            if bufferingState != oldValue || !playbackEdgeTriggered {
                self.executeClosureOnMainQueueIfNecessary {
                    self.playerDelegate?.playerBufferingStateDidChange(self)
                }
            }
        }
    }
    
    /// Playback buffering size in seconds.
    open var bufferSizeInSeconds: Double = 10 {
        didSet {
            self._playerItem?.preferredForwardBufferDuration = self.bufferSizeInSeconds
        }
    }
    
    /// Playback is not automatically triggered from state changes when true.
    open var playbackEdgeTriggered: Bool = true
    
    /// Maximum duration of playback.
    open var maximumDuration: TimeInterval {
        guard let playerItem = self._playerItem else {
            return CMTimeGetSeconds(CMTime.indefinite)
        }
        return CMTimeGetSeconds(playerItem.duration)
    }
    
    /// Media playback's current time interval in seconds.
    open var currentTimeInterval: TimeInterval {
        guard let playerItem = self._playerItem else {
            return CMTimeGetSeconds(CMTime.indefinite)
        }
        return CMTimeGetSeconds(playerItem.currentTime())
    }
    
    /// Media playback's current time.
    open var currentTime: CMTime {
        guard let playerItem = self._playerItem else {
            return CMTime.indefinite
        }
        return playerItem.currentTime()
    }
    
    /// self.view as PlayerView type
    public var playerView: PlayerView {
        return self._playerView
    }
    
    /// Return the av player layer for consumption by things such as Picture in Picture
    public func playerLayer() -> AVPlayerLayer? {
        return self._playerView.playerLayer
    }
    
    /// Indicates the desired limit of network bandwidth consumption for this item.
    open var preferredPeakBitRate: Double = 0 {
        didSet {
            self._playerItem?.preferredPeakBitRate = self.preferredPeakBitRate
        }
    }
    
    /// Indicates a preferred upper limit on the resolution of the video to be downloaded.
    @available(iOS 11.0, tvOS 11.0, *)
    open var preferredMaximumResolution: CGSize {
        get {
            return self._playerItem?.preferredMaximumResolution ?? CGSize.zero
        }
        set {
            self._playerItem?.preferredMaximumResolution = newValue
            self._preferredMaximumResolution = newValue
        }
    }
    
    // MARK: - private instance vars
    
    internal var _asset: AVAsset? {
        didSet {
            if self._asset != nil {
                self.setupPlayerItem(nil)
            }
        }
    }
    internal lazy var _avplayer: AVPlayer = {
        let avplayer = AVPlayer()
        avplayer.actionAtItemEnd = .pause
        return avplayer
    }()
    internal var _playerItem: AVPlayerItem?
    
    internal var _playerObservers = [NSKeyValueObservation]()
    internal var _playerItemObservers = [NSKeyValueObservation]()
    internal var _playerLayerObserver: NSKeyValueObservation?
    internal var _playerTimeObserver: Any?
    
    internal var _playerView: PlayerView = PlayerView(frame: .zero)
    internal var _seekTimeRequested: CMTime?
    internal var _lastBufferTime: Double = 0
    internal var _preferredMaximumResolution: CGSize = .zero
    
    // Boolean that determines if the user or calling coded has trigged autoplay manually.
    internal var _hasAutoplayActivated: Bool = true
    
    // MARK: - object lifecycle
    
    public convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    deinit {
        self._avplayer.pause()
        self.setupPlayerItem(nil)
        
        self.removePlayerObservers()
        
        self.playerDelegate = nil
        self.removeApplicationObservers()
        
        self.playbackDelegate = nil
        self.removePlayerLayerObservers()
        
        self._playerView.player = nil
    }
    
    // MARK: - view lifecycle
    
    open override func loadView() {
        super.loadView()
        self._playerView.frame = self.view.bounds
        self.view = self._playerView
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        self._playerView.player = self._avplayer
        
        if let url = self.url {
            setup(url: url)
        } else if let asset = self.asset {
            setupAsset(asset)
        }
        
        self.addPlayerLayerObservers()
        self.addPlayerObservers()
        self.addApplicationObservers()
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.playbackState == .playing {
            self.pause()
        }
    }
    
}

// MARK: - performance

extension Player {
    
    /// Total time spent playing.
    public var totalDurationWatched: TimeInterval {
        var totalDurationWatched = 0.0
        if let accessLog = self._playerItem?.accessLog(), accessLog.events.isEmpty == false {
            for event in accessLog.events where event.durationWatched > 0 {
                totalDurationWatched += event.durationWatched
            }
        }
        return totalDurationWatched
    }
    
    /// Time weighted value of the variant indicated bitrate. Measure of overall stream quality.
    var timeWeightedIBR: Double {
        var timeWeightedIBR = 0.0
        let totalDurationWatched = self.totalDurationWatched
        
        if let accessLog = self._playerItem?.accessLog(), totalDurationWatched > 0 {
            for event in accessLog.events {
                if event.durationWatched > 0 && event.indicatedBitrate > 0 {
                    let eventTimeWeight = event.durationWatched / totalDurationWatched
                    timeWeightedIBR += event.indicatedBitrate * eventTimeWeight
                }
            }
        }
        return timeWeightedIBR
    }
    
    /// Stall rate measured in stalls per hour. Normalized measure of stream interruptions caused by stream buffer depleation.
    var stallRate: Double {
        var totalNumberOfStalls = 0
        let totalHoursWatched = self.totalDurationWatched / 3600
        
        if let accessLog = self._playerItem?.accessLog(), totalDurationWatched > 0 {
            for event in accessLog.events {
                totalNumberOfStalls += event.numberOfStalls
            }
        }
        return Double(totalNumberOfStalls) / totalHoursWatched
    }
    
}

// MARK: - actions

extension Player {
    
    /// Begins playback of the media from the beginning.
    public func playFromBeginning() {
        self.playbackDelegate?.playerPlaybackWillStartFromBeginning(self)
        self._avplayer.seek(to: CMTime.zero)
        self.playFromCurrentTime()
    }
    
    /// Begins playback of the media from the current time.
    public func playFromCurrentTime() {
        if !self.autoplay {
            // External call to this method with autoplay disabled. Re-activate it before calling play.
            self._hasAutoplayActivated = true
        }
        self.play()
    }
    
    fileprivate func play() {
        if self.autoplay || self._hasAutoplayActivated {
            self.playbackState = .playing
            self._avplayer.playImmediately(atRate: rate)
        }
    }
    
    /// Pauses playback of the media.
    public func pause() {
        if self.playbackState != .playing {
            return
        }
        
        self._avplayer.pause()
        self.playbackState = .paused
    }
    
    /// Stops playback of the media.
    public func stop() {
        if self.playbackState == .stopped {
            return
        }
        
        self._avplayer.pause()
        self.playbackState = .stopped
        self.playbackDelegate?.playerPlaybackDidEnd(self)
    }
    
    /// Updates playback to the specified time.
    ///
    /// - Parameters:
    ///   - time: The time to switch to move the playback.
    ///   - completionHandler: Call block handler after seeking/
    public func seek(to time: CMTime, completionHandler: ((Bool) -> Swift.Void)? = nil) {
        if let playerItem = self._playerItem {
            return playerItem.seek(to: time, completionHandler: completionHandler)
        } else {
            self._seekTimeRequested = time
        }
    }
    
    /// Updates the playback time to the specified time bound.
    ///
    /// - Parameters:
    ///   - time: The time to switch to move the playback.
    ///   - toleranceBefore: The tolerance allowed before time.
    ///   - toleranceAfter: The tolerance allowed after time.
    ///   - completionHandler: call block handler after seeking
    public func seekToTime(
        to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
        completionHandler: ((Bool) -> Swift.Void)? = nil
    ) {
        if let playerItem = self._playerItem {
            return playerItem.seek(
                to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter,
                completionHandler: completionHandler)
        }
    }
    
    /// Captures a snapshot of the current Player asset.
    ///
    /// - Parameter completionHandler: Returns a UIImage of the requested video frame. (Great for thumbnails!)
    public func takeSnapshot(completionHandler: ((_ image: UIImage?, _ error: Error?) -> Void)?) {
        guard let asset = self._playerItem?.asset else {
            DispatchQueue.main.async {
                completionHandler?(nil, nil)
            }
            return
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let currentTime = self._playerItem?.currentTime() ?? CMTime.zero
        
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: currentTime)]) {
            (requestedTime, image, actualTime, result, error) in
            guard let image = image else {
                DispatchQueue.main.async {
                    completionHandler?(nil, error)
                }
                return
            }
            
            switch result {
            case .succeeded:
                let uiimage = UIImage(cgImage: image)
                DispatchQueue.main.async {
                    completionHandler?(uiimage, nil)
                }
                break
            case .failed, .cancelled:
                fallthrough
            @unknown default:
                DispatchQueue.main.async {
                    completionHandler?(nil, nil)
                }
                break
            }
        }
    }
    
}

// MARK: - loading funcs

extension Player {
    
    fileprivate func setup(url: URL) {
        guard isViewLoaded else { return }
        
        // ensure everything is reset beforehand
        if self.playbackState == .playing {
            self.pause()
        }
        
        // Reset autoplay flag since a new url is set.
        self._hasAutoplayActivated = false
        if self.autoplay {
            self.playbackState = .playing
        } else {
            self.playbackState = .stopped
        }
        
        self.setupPlayerItem(nil)
        
        let asset = AVURLAsset(url: url, options: .none)
        self.setupAsset(asset)
    }
    
    fileprivate func setupAsset(
        _ asset: AVAsset
    ) {
        guard isViewLoaded else { return }
        
        if self.playbackState == .playing {
            self.pause()
        }
        
        self.bufferingState = .unknown
        
        self._asset = asset
        
        Task {
            guard let asset = self._asset else {
                return
            }
            do {
                let (_, isPlayable, _) = try await asset.load(.tracks, .isPlayable, .duration)
                guard isPlayable else {
                    self.playbackState = .failed
                    self.executeClosureOnMainQueueIfNecessary {
                        self.playerDelegate?.player(self, didFailWithError: PlayerError.failed)
                    }
                    return
                }
            } catch {
                self.playbackState = .failed
                self.executeClosureOnMainQueueIfNecessary {
                    self.playerDelegate?.player(self, didFailWithError: error)
                }
                return
            }
            
            let statusChecks: [() -> Error?] = [
                {
                    if case .failed(let e) = asset.status(of: .tracks) { return e }
                    return nil
                },
                {
                    if case .failed(let e) = asset.status(of: .isPlayable) { return e }
                    return nil
                },
                {
                    if case .failed(let e) = asset.status(of: .duration) { return e }
                    return nil
                },
            ]

            // 查找第一个加载失败的错误
            if let firstError = statusChecks.lazy.compactMap({ $0() }).first {
                self.playbackState = .failed
                self.executeClosureOnMainQueueIfNecessary {
                    self.playerDelegate?.player(self, didFailWithError: firstError)
                }
                return
            }
            
            let playerItem = AVPlayerItem(asset: asset)
            self.setupPlayerItem(playerItem)
        }
    }
    
    fileprivate func setupPlayerItem(_ playerItem: AVPlayerItem?) {
        
        self.removePlayerItemObservers()
        
        if let currentPlayerItem = self._playerItem {
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemDidPlayToEndTime, object: currentPlayerItem)
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemFailedToPlayToEndTime, object: currentPlayerItem)
        }
        
        self._playerItem = playerItem
        
        self._playerItem?.audioTimePitchAlgorithm = .spectral
        self._playerItem?.preferredPeakBitRate = self.preferredPeakBitRate
        if #available(iOS 11.0, tvOS 11.0, *) {
            self._playerItem?.preferredMaximumResolution = self._preferredMaximumResolution
        }
        
        self._playerItem?.preferredForwardBufferDuration = self.bufferSizeInSeconds
        
        if let seek = self._seekTimeRequested, self._playerItem != nil {
            self._seekTimeRequested = nil
            self.seek(to: seek)
        }
        
        if let updatedPlayerItem = self._playerItem {
            self.addPlayerItemObservers()
            NotificationCenter.default.addObserver(
                self, selector: #selector(playerItemDidPlayToEndTime(_:)), name: .AVPlayerItemDidPlayToEndTime,
                object: updatedPlayerItem)
            NotificationCenter.default.addObserver(
                self, selector: #selector(playerItemFailedToPlayToEndTime(_:)),
                name: .AVPlayerItemFailedToPlayToEndTime, object: updatedPlayerItem)
        }
        
        self._avplayer.replaceCurrentItem(with: self._playerItem)
        self._avplayer.rate = rate
        
        // update new playerItem settings
        if self.playbackLoops {
            self._avplayer.actionAtItemEnd = .none
        } else {
            self._avplayer.actionAtItemEnd = .pause
        }
    }
    
}

// MARK: - NSNotifications

extension Player {
    
    // MARK: - UIApplication
    
    internal func addApplicationObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleApplicationWillResignActive(_:)),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleApplicationDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleApplicationDidEnterBackground(_:)),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleApplicationWillEnterForeground(_:)),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    internal func removeApplicationObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - AVPlayerItem handlers
    
    @objc internal func playerItemDidPlayToEndTime(_ aNotification: Notification) {
        self.executeClosureOnMainQueueIfNecessary {
            if self.playbackLoops {
                self.playbackDelegate?.playerPlaybackWillLoop(self)
                self._avplayer.seek(to: CMTime.zero)
                self._avplayer.play()
                self._avplayer.rate = self.rate
                self.playbackDelegate?.playerPlaybackDidLoop(self)
            } else if self.playbackFreezesAtEnd {
                self.stop()
            } else {
                self._avplayer.seek(
                    to: CMTime.zero,
                    completionHandler: { _ in
                        self.stop()
                    })
            }
        }
    }
    
    @objc internal func playerItemFailedToPlayToEndTime(_ aNotification: Notification) {
        self.playbackState = .failed
    }
    
    // MARK: - UIApplication handlers
    
    @objc internal func handleApplicationWillResignActive(_ aNotification: Notification) {
        if self.playbackState == .playing && self.playbackPausesWhenResigningActive {
            self.pause()
        }
    }
    
    @objc internal func handleApplicationDidBecomeActive(_ aNotification: Notification) {
        if self.playbackState == .paused && self.playbackResumesWhenBecameActive {
            self.play()
        }
    }
    
    @objc internal func handleApplicationDidEnterBackground(_ aNotification: Notification) {
        if self.playbackState == .playing && self.playbackPausesWhenBackgrounded {
            self.pause()
        }
    }
    
    @objc internal func handleApplicationWillEnterForeground(_ aNoticiation: Notification) {
        if self.playbackState != .playing && self.playbackResumesWhenEnteringForeground {
            self.play()
        }
    }
    
}

// MARK: - KVO

extension Player {
    
    // MARK: - AVPlayerItemObservers
    
    internal func addPlayerItemObservers() {
        guard let playerItem = self._playerItem else {
            return
        }
        
        self._playerItemObservers.append(
            playerItem.observe(\.isPlaybackBufferEmpty, options: [.new, .old]) { [weak self] (object, change) in
                if object.isPlaybackBufferEmpty {
                    self?.bufferingState = .delayed
                }
                
                switch object.status {
                case .failed:
                    self?.playbackState = PlaybackState.failed
                default:
                    break
                }
            })
        
        self._playerItemObservers.append(
            playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .old]) { [weak self] (object, change) in
                guard let strongSelf = self else {
                    return
                }
                
                if object.isPlaybackLikelyToKeepUp {
                    strongSelf.bufferingState = .ready
                    if strongSelf.playbackState == .playing {
                        strongSelf.playFromCurrentTime()
                    }
                }
                
                switch object.status {
                case .failed:
                    strongSelf.playbackState = PlaybackState.failed
                    break
                default:
                    break
                }
            })
        
        self._playerItemObservers.append(
            playerItem.observe(\.loadedTimeRanges, options: [.new, .old]) { [weak self] (object, change) in
                guard let strongSelf = self else {
                    return
                }
                
                let timeRanges = object.loadedTimeRanges
                if let timeRange = timeRanges.first?.timeRangeValue {
                    let bufferedTime = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration))
                    if strongSelf._lastBufferTime != bufferedTime {
                        strongSelf._lastBufferTime = bufferedTime
                        strongSelf.executeClosureOnMainQueueIfNecessary {
                            strongSelf.playerDelegate?.playerBufferTimeDidChange(bufferedTime)
                        }
                    }
                }
                
                let currentTime = CMTimeGetSeconds(object.currentTime())
                let passedTime =
                    strongSelf._lastBufferTime <= 0 ? currentTime : (strongSelf._lastBufferTime - currentTime)
                
                if (passedTime >= strongSelf.bufferSizeInSeconds
                    || strongSelf._lastBufferTime == strongSelf.maximumDuration || timeRanges.first == nil)
                    && strongSelf.playbackState == .playing
                {
                    strongSelf.play()
                }
            })
    }
    
    internal func removePlayerItemObservers() {
        for observer in self._playerItemObservers {
            observer.invalidate()
        }
        self._playerItemObservers.removeAll()
    }
    
    // MARK: - AVPlayerLayerObservers
    
    internal func addPlayerLayerObservers() {
        self._playerLayerObserver = self._playerView.playerLayer.observe(\.isReadyForDisplay, options: [.new, .old]) {
            [weak self] (object, change) in
            self?.executeClosureOnMainQueueIfNecessary {
                if let strongSelf = self {
                    strongSelf.playerDelegate?.playerReady(strongSelf)
                }
            }
        }
    }
    
    internal func removePlayerLayerObservers() {
        self._playerLayerObserver?.invalidate()
        self._playerLayerObserver = nil
    }
    
    // MARK: - AVPlayerObservers
    
    internal func addPlayerObservers() {
        self._playerTimeObserver = self._avplayer.addPeriodicTimeObserver(
            forInterval: CMTimeMake(value: 1, timescale: 100), queue: DispatchQueue.main,
            using: { [weak self] timeInterval in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.playbackDelegate?.playerCurrentTimeDidChange(strongSelf)
            })
        
        if #available(iOS 10.0, tvOS 10.0, *) {
            self._playerObservers.append(
                self._avplayer.observe(\.timeControlStatus, options: [.new, .old]) { [weak self] (object, change) in
                    switch object.timeControlStatus {
                    case .paused:
                        self?.playbackState = .paused
                    case .playing:
                        self?.playbackState = .playing
                    case .waitingToPlayAtSpecifiedRate:
                        fallthrough
                    @unknown default:
                        break
                    }
                })
        }
        
    }
    
    internal func removePlayerObservers() {
        if let observer = self._playerTimeObserver {
            self._avplayer.removeTimeObserver(observer)
        }
        for observer in self._playerObservers {
            observer.invalidate()
        }
        self._playerObservers.removeAll()
    }
    
}

// MARK: - queues

extension Player {
    
    internal func executeClosureOnMainQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.async(execute: closure)
        }
    }
    
}

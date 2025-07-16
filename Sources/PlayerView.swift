//
//  PlayerView.swift
//
//  (\(\
//  ( -.-)
//  o_(")(")
//  -----------------------
//  Created by jeffy on 7/15/25.
//

import AVFoundation
import UIKit

// MARK: - PlayerView

public class PlayerView: UIView {
    
    // MARK: - overrides
    
    public override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    // MARK: - internal properties
    
    internal var playerLayer: AVPlayerLayer {
        return self.layer as! AVPlayerLayer
    }
    
    // MARK: - public properties
    
    public var player: AVPlayer? {
        get {
            return self.playerLayer.player
        }
        set {
            self.playerLayer.player = newValue
            self.playerLayer.isHidden = (self.playerLayer.player == nil)
        }
    }
    
    public var playerBackgroundColor: UIColor? {
        get {
            if let cgColor = self.playerLayer.backgroundColor {
                return UIColor(cgColor: cgColor)
            }
            return nil
        }
        set {
            self.playerLayer.backgroundColor = newValue?.cgColor
        }
    }
    
    public var playerFillMode: Player.FillMode {
        get {
            return self.playerLayer.videoGravity
        }
        set {
            self.playerLayer.videoGravity = newValue
        }
    }
    
    public var isReadyForDisplay: Bool {
        return self.playerLayer.isReadyForDisplay
    }
    
    // MARK: - object lifecycle
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.playerLayer.isHidden = true
        self.playerFillMode = .resizeAspect
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.playerLayer.isHidden = true
        self.playerFillMode = .resizeAspect
    }
    
    deinit {
        self.player?.pause()
        self.player = nil
    }
    
}

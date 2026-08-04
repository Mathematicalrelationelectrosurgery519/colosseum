import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Plays multi-frame images (GIF) via AppKit — SwiftUI `Image` only shows frame 0.
struct AnimatedImageView: NSViewRepresentable {
    let url: URL
    var imageScaling: NSImageScaling = .scaleProportionallyUpOrDown

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = imageScaling
        view.imageAlignment = .alignCenter
        view.animates = true
        context.coordinator.load(url: url, into: view)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.imageScaling = imageScaling
        if context.coordinator.currentURL != url {
            context.coordinator.load(url: url, into: nsView)
        } else {
            // Re-assert after SwiftUI updates; animates must be true after image is set.
            nsView.animates = true
        }
    }

    final class Coordinator {
        var currentURL: URL?

        func load(url: URL, into view: NSImageView) {
            currentURL = url
            view.image = NSImage(contentsOf: url)
            view.animates = true
        }
    }
}

/// Wraps `AVPlayerView` instead of SwiftUI `VideoPlayer`, which can abort when
/// AVKit isn't fully linked in SPM/distributed macOS builds.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    var showsControls: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = showsControls ? .inline : .none
        view.videoGravity = videoGravity
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.controlsStyle = showsControls ? .inline : .none
        nsView.videoGravity = videoGravity
        if nsView.player !== player {
            nsView.player = player
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

/// Owns an `AVQueuePlayer` + `AVPlayerLooper` so clips repeat cleanly.
final class LoopingVideoPlayer {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL, muted: Bool) {
        let queue = AVQueuePlayer()
        queue.isMuted = muted
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
    }

    func play() {
        player.play()
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }

    deinit {
        player.pause()
        looper?.disableLooping()
    }
}

enum VideoPlayback {
    static func looping(url: URL, muted: Bool) -> LoopingVideoPlayer {
        LoopingVideoPlayer(url: url, muted: muted)
    }
}

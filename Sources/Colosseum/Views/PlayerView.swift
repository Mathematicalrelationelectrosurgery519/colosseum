import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Plays multi-frame images (GIF) via AppKit — SwiftUI `Image` only shows frame 0.
///
/// Uses a container that reports no intrinsic size so large GIFs don't blow up
/// LazyVGrid cells the way a bare `NSImageView` would.
struct AnimatedImageView: NSViewRepresentable {
    let url: URL
    var imageScaling: NSImageScaling = .scaleProportionallyUpOrDown

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = IntrinsicSizeIgnoringView()
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = imageScaling
        imageView.imageAlignment = .alignCenter
        imageView.animates = true
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        context.coordinator.imageView = imageView
        context.coordinator.load(url: url)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.imageView?.imageScaling = imageScaling
        if context.coordinator.currentURL != url {
            context.coordinator.load(url: url)
        } else {
            // Re-assert after SwiftUI updates; animates must be true after image is set.
            context.coordinator.imageView?.animates = true
        }
    }

    final class Coordinator {
        var currentURL: URL?
        weak var imageView: NSImageView?

        func load(url: URL) {
            currentURL = url
            guard let imageView else { return }
            imageView.image = NSImage(contentsOf: url)
            imageView.animates = true
        }
    }
}

/// `NSView` that never proposes its children's intrinsic size to SwiftUI layout.
private final class IntrinsicSizeIgnoringView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var isFlipped: Bool { true }
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

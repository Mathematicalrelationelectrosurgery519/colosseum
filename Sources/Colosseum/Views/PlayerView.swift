import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Plays multi-frame images (GIF) via AppKit — SwiftUI `Image` only shows frame 0.
///
/// Always adopts the size SwiftUI proposes. A bare `NSImageView` otherwise reports
/// the GIF's full pixel size and blows up LazyVGrid cells.
struct AnimatedImageView: NSViewRepresentable {
    let url: URL
    var imageScaling: NSImageScaling = .scaleProportionallyUpOrDown

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = ClippingContainerView()
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = imageScaling
        imageView.imageAlignment = .alignCenter
        imageView.animates = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
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

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width
        let height = proposal.height
        switch (width, height) {
        case let (w?, h?) where w.isFinite && h.isFinite && w > 0 && h > 0:
            return CGSize(width: w, height: h)
        case let (w?, nil) where w.isFinite && w > 0:
            return CGSize(width: w, height: w)
        case let (nil, h?) where h.isFinite && h > 0:
            return CGSize(width: h, height: h)
        default:
            return .zero
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

/// Clips AppKit drawing and never contributes an intrinsic size to SwiftUI.
private final class ClippingContainerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
    private var statusObservation: NSKeyValueObservation?
    /// Fired on the main queue once the current item can present frames.
    var onReady: (() -> Void)?

    init(url: URL, muted: Bool) {
        let queue = AVQueuePlayer()
        queue.isMuted = muted
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                self?.onReady?()
            }
        }
    }

    func play() {
        player.play()
    }

    func stop() {
        statusObservation?.invalidate()
        statusObservation = nil
        onReady = nil
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }

    deinit {
        statusObservation?.invalidate()
        player.pause()
        looper?.disableLooping()
    }
}

enum VideoPlayback {
    static func looping(url: URL, muted: Bool) -> LoopingVideoPlayer {
        LoopingVideoPlayer(url: url, muted: muted)
    }
}

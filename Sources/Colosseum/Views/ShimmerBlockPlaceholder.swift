import AppKit
import SwiftUI

/// Square (or freeform) loading stand-in with a quick bottom-leading → top-trailing wipe.
struct ShimmerBlockPlaceholder: View {
    /// When true, locks to a 1:1 block aspect (grid cells). When false, fills the offered frame (media pane).
    var square: Bool = true
    var showsBorder: Bool = true

    var body: some View {
        Group {
            if square {
                shimmer
                    .aspectRatio(1, contentMode: .fit)
            } else {
                shimmer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .overlay {
            if showsBorder {
                Rectangle().stroke(ColosseumTheme.border, lineWidth: 0.5)
            }
        }
        .accessibilityLabel("Loading")
    }

    private var shimmer: some View {
        // Quick wipe — under half a second per pass, BL → TR.
        TimelineView(.animation(minimumInterval: 1.0 / 40.0)) { context in
            let cycle = 0.42
            let t = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycle) / cycle
            let x = t * 1.55 - 0.28
            ZStack {
                ColosseumTheme.surface
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: clamp(x - 0.14)),
                        .init(color: Color.white.opacity(0.12), location: clamp(x)),
                        .init(color: .clear, location: clamp(x + 0.14))
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            }
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

/// Loads a remote image over a shimmer placeholder, then crossfades the media in.
struct ShimmerRemoteImage<Failure: View>: View {
    let url: URL
    var square: Bool = true
    var showsBorder: Bool = true
    var contentPadding: CGFloat = 0
    var failure: () -> Failure

    @State private var image: Image?
    @State private var didFail = false
    @State private var loadID = 0

    private var showMedia: Bool { image != nil }
    private var showFailure: Bool { didFail && image == nil }

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .padding(contentPadding)
                    .transition(ColosseumMotion.mediaReveal)
            } else if showFailure {
                failure()
                    .padding(contentPadding)
                    .transition(.opacity)
            } else {
                ShimmerBlockPlaceholder(square: square, showsBorder: showsBorder)
                    .padding(contentPadding)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: square ? nil : .infinity)
        .animation(ColosseumMotion.standard, value: showMedia)
        .animation(ColosseumMotion.soft, value: showFailure)
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        loadID += 1
        let ticket = loadID
        image = nil
        didFail = false

        let loaded = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value

        guard ticket == loadID else { return }
        if let loaded {
            image = Image(nsImage: loaded)
        } else {
            didFail = true
        }
    }
}

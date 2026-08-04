import AppKit
import AVFoundation
import SwiftUI

struct AddBlockCell: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(ColosseumTheme.surface)
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ColosseumTheme.primaryText)
            VStack {
                Spacer()
                HStack {
                    Text("⌘↩")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                        .padding(8)
                    Spacer()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .blockTagBorder(tags: [], lineWidth: 1)
    }
}

struct MediaBlockCell: View {
    let block: Block
    var isSelected: Bool = false

    @State private var isHovering = false
    @State private var thumbImage: NSImage?
    @StateObject private var videoSession = CellVideoSession()

    private var tags: [String] { TagParser.tags(in: block.notes) }

    private var wantsPlayback: Bool { isHovering || isSelected }

    private var shouldPlayGIF: Bool {
        block.isAnimatedImage && wantsPlayback
    }

    private var shouldPlayVideo: Bool {
        block.kind == .video && wantsPlayback
    }

    var body: some View {
        // Size from a square surface (like AddBlockCell), never from media intrinsic size.
        // Cached thumb stays under live media so selection/hover does not reload-flash.
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(ColosseumTheme.surface)

            thumbnail
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shouldPlayVideo, let player = videoSession.player {
                PlayerView(
                    player: player,
                    showsControls: false,
                    videoGravity: .resizeAspect
                )
                .opacity(videoSession.isReady ? 1 : 0)
                .transaction { $0.animation = nil }
                .allowsHitTesting(false)
            } else if shouldPlayGIF, let path = block.localRelativePath {
                AnimatedImageView(url: MediaLibrary.absoluteURL(relativePath: path))
                    .allowsHitTesting(false)
            }

            if block.kind == .video, !shouldPlayVideo {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .blockTagBorder(tags: tags, lineWidth: tags.isEmpty ? 0.5 : ColosseumTheme.taggedBorderWidth)
        .onAppear {
            loadThumbnailIfNeeded()
            syncVideoPlayback()
        }
        .onContinuousHover { phase in
            guard block.kind == .video || block.isAnimatedImage else { return }
            switch phase {
            case .active:
                if !isHovering {
                    isHovering = true
                    syncVideoPlayback()
                }
            case .ended:
                if isHovering {
                    isHovering = false
                    syncVideoPlayback()
                }
            }
        }
        .onChange(of: isSelected) { _, _ in
            syncVideoPlayback()
        }
        .onDisappear { videoSession.stop() }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbImage {
            Image(nsImage: thumbImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: block.kind == .video ? "video" : "photo")
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(ColosseumTheme.tertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ColosseumTheme.surface)
    }

    private func loadThumbnailIfNeeded() {
        guard thumbImage == nil else { return }
        guard let path = block.thumbRelativePath ?? block.localRelativePath else { return }
        let url = MediaLibrary.absoluteURL(relativePath: path)
        thumbImage = NSImage(contentsOf: url)
    }

    private func syncVideoPlayback() {
        guard block.kind == .video else { return }
        if shouldPlayVideo {
            guard let path = block.localRelativePath else { return }
            videoSession.start(url: MediaLibrary.absoluteURL(relativePath: path))
        } else {
            videoSession.stop()
        }
    }
}

struct TextBlockCell: View {
    let block: Block
    private var tags: [String] { TagParser.tags(in: block.notes) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ColosseumTheme.canvas)
            Text(block.textBody.isEmpty ? "Empty note" : block.textBody)
                .font(.system(size: 12))
                .foregroundStyle(ColosseumTheme.primaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
        .aspectRatio(1, contentMode: .fit)
        .blockTagBorder(tags: tags, lineWidth: tags.isEmpty ? 1 : ColosseumTheme.taggedBorderWidth)
    }
}

struct LinkBlockCell: View {
    let block: Block
    private var tags: [String] { TagParser.tags(in: block.notes) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ColosseumTheme.surface)
            VStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(ColosseumTheme.secondaryText)
                Text(block.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ColosseumTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 10)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .blockTagBorder(tags: tags, lineWidth: tags.isEmpty ? 1 : ColosseumTheme.taggedBorderWidth)
    }
}

struct ArenaBlockCell: View {
    let block: Block
    private var tags: [String] { TagParser.tags(in: block.notes) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ColosseumTheme.canvas)
            VStack(spacing: 6) {
                Text(block.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ColosseumTheme.remoteBoardTitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let owner = block.arenaOwnerName {
                    Text("by \(owner)")
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.secondaryText)
                }
                Text("\(block.arenaBlockCount) blocks")
                    .font(.system(size: 11))
                    .foregroundStyle(ColosseumTheme.secondaryText)
                if let updated = block.arenaUpdatedAt {
                    Text(ColosseumFormatters.relativeDate(updated))
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                }
            }
            .padding(14)
        }
        .aspectRatio(1, contentMode: .fit)
        .blockTagBorder(tags: tags, lineWidth: tags.isEmpty ? 1 : ColosseumTheme.taggedBorderWidth)
    }
}

struct NestedBoardCell: View {
    let board: Board
    private var tags: [String] { TagParser.tags(in: board.notes) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ColosseumTheme.canvas)
            VStack(spacing: 6) {
                Text(board.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ColosseumTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text("\(board.contentCount) blocks")
                    .font(.system(size: 11))
                    .foregroundStyle(ColosseumTheme.secondaryText)
                Text(ColosseumFormatters.relativeDate(board.updatedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(ColosseumTheme.tertiaryText)
                Text(ColosseumFormatters.byteCount(board.storageBytes))
                    .font(.system(size: 11))
                    .foregroundStyle(ColosseumTheme.tertiaryText)
            }
            .padding(14)
        }
        .aspectRatio(1, contentMode: .fit)
        .blockTagBorder(tags: tags, lineWidth: tags.isEmpty ? 1 : ColosseumTheme.taggedBorderWidth)
    }
}

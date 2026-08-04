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

    @State private var isHovering = false
    @State private var hoverPlayer: LoopingVideoPlayer?

    private var tags: [String] { TagParser.tags(in: block.notes) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if block.kind == .video, isHovering, let hoverPlayer {
                    PlayerView(
                        player: hoverPlayer.player,
                        showsControls: false,
                        videoGravity: .resizeAspect
                    )
                    .allowsHitTesting(false)
                    .transition(ColosseumMotion.fade)
                } else if block.isAnimatedImage, let path = block.localRelativePath {
                    // Autoplay original GIF — thumbs are static JPEG frame 0.
                    AnimatedImageView(url: MediaLibrary.absoluteURL(relativePath: path))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .allowsHitTesting(false)
                } else {
                    thumbnail
                        .transition(ColosseumMotion.fade)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .background(ColosseumTheme.surface)
            .animation(ColosseumMotion.soft, value: isHovering)

            if block.kind == .video, !isHovering {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(8)
                    .transition(ColosseumMotion.fade)
            }
        }
        .blockTagBorder(tags: tags, lineWidth: tags.isEmpty ? 0.5 : ColosseumTheme.taggedBorderWidth)
        .onHover { hovering in
            guard block.kind == .video else { return }
            withAnimation(ColosseumMotion.soft) {
                isHovering = hovering
            }
            if hovering {
                startHoverPlayback()
            } else {
                stopHoverPlayback()
            }
        }
        .onDisappear { stopHoverPlayback() }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let path = block.thumbRelativePath ?? block.localRelativePath {
            let url = MediaLibrary.absoluteURL(relativePath: path)
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder
            }
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

    private func startHoverPlayback() {
        stopHoverPlayback()
        guard let path = block.localRelativePath else { return }
        let url = MediaLibrary.absoluteURL(relativePath: path)
        let player = VideoPlayback.looping(url: url, muted: true)
        hoverPlayer = player
        player.play()
    }

    private func stopHoverPlayback() {
        hoverPlayer?.stop()
        hoverPlayer = nil
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

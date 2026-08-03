import AppKit
import SwiftUI

struct AddBlockCell: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))

            Text("Add")
                .font(.system(size: 11))
                .foregroundStyle(ColosseumTheme.secondaryText)
        }
    }
}

struct MediaBlockCell: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                thumbnail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .background(ColosseumTheme.surface)

                if block.kind == .video {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(8)
                }
            }
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 0.5))

            Text(block.displayTitle)
                .font(.system(size: 11))
                .foregroundStyle(ColosseumTheme.secondaryText)
                .lineLimit(1)
        }
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
}

struct TextBlockCell: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))

            Text(block.displayTitle)
                .font(.system(size: 11))
                .foregroundStyle(ColosseumTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

struct LinkBlockCell: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))

            Text(block.sourceURL ?? "Link")
                .font(.system(size: 11))
                .foregroundStyle(ColosseumTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

struct ArenaBlockCell: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(ColosseumTheme.canvas)
                VStack(spacing: 6) {
                    Text(block.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ColosseumTheme.primaryText)
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
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))

            Text("are.na")
                .font(.system(size: 11))
                .foregroundStyle(ColosseumTheme.secondaryText)
        }
    }
}

struct NestedBoardCell: View {
    let board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                }
                .padding(14)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))

            Text(board.title)
                .font(.system(size: 11))
                .foregroundStyle(ColosseumTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

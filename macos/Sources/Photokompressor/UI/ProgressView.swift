import SwiftUI

/// Direct port of ProgressWindow.xaml.
struct ProgressView: View {
    @ObservedObject var viewModel: ProgressViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.bg)
                .shadow(color: Color(hex: 0x243044, opacity: 0.3), radius: 34, x: 0, y: 7)

            VStack(spacing: 0) {
                header
                results
                progressAndTotals
                footer
            }
            .padding(EdgeInsets(top: 20, leading: 26, bottom: 24, trailing: 26))
        }
        .frame(width: 596, height: 656)
        .onAppear { viewModel.start() }
    }

    private var header: some View {
        // See OptionsView.header / WindowDragBackground's doc comment.
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.titleText)
                    .font(Theme.font(size: 27, .extraLight))
                    .foregroundColor(Theme.textHi)
                    .allowsHitTesting(false)
                Text(viewModel.countText)
                    .font(Theme.font(size: 13, .light))
                    .foregroundColor(Theme.textLo)
                    .allowsHitTesting(false)
            }
            Spacer()
            RoundGlyphButton(kind: .close) { viewModel.cancel() }
        }
        .background(WindowDragBackground())
        .padding(.bottom, 16)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.items) { item in
                    ResultRow(item: item)
                }
            }
        }
    }

    private var progressAndTotals: some View {
        VStack(alignment: .leading, spacing: 14) {
            NeuProgressBar(progress: viewModel.overallProgress)
            Text(viewModel.totalsText)
                .font(Theme.font(size: 20, .regular))
                .foregroundColor(Theme.textHi)
        }
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 10) {
                Button("Back") { viewModel.onRequestClose?() }
                    .buttonStyle(SoftButtonStyle())
                    .frame(width: 104)
                    .disabled(!viewModel.finished)
                    .opacity(viewModel.finished ? 1 : 0.4)
                Button("Open output folder") { viewModel.openOutputFolder() }
                    .buttonStyle(SoftButtonStyle())
                    .frame(width: 178)
                    .disabled(!viewModel.canOpenOutputFolder)
                    .opacity(viewModel.canOpenOutputFolder ? 1 : 0.4)
            }
            Spacer()
            Button(viewModel.finished ? "Done" : (viewModel.cancelling ? "Cancelling…" : "Cancel")) {
                viewModel.cancel()
            }
            .buttonStyle(AccentButtonStyle())
            .frame(width: 140)
            .disabled(viewModel.cancelling && !viewModel.finished)
            .opacity(viewModel.cancelling && !viewModel.finished ? 0.45 : 1)
        }
        .padding(.top, 18)
    }
}

private struct ResultRow: View {
    @ObservedObject var item: ResultRowItem

    var body: some View {
        ResultCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(Theme.font(size: 13.5, .semibold))
                        .foregroundColor(Theme.textHi)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.detail)
                        .font(Theme.font(size: 11.5, .light))
                        .foregroundColor(Theme.textLo)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(item.badge)
                    .font(Theme.font(size: 12.5, .semibold))
                    .foregroundColor(badgeForeground)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(badgeBackground))
            }
        }
    }

    private var badgeBackground: Color {
        switch item.kind {
        case .done: return Theme.accentBlue
        case .kept: return Color(hex: 0xFFF3DC)
        case .failed: return Color(hex: 0xFFE6E4)
        default: return Theme.sunken
        }
    }

    private var badgeForeground: Color {
        switch item.kind {
        case .done: return .white
        case .kept: return Theme.warn
        case .failed: return Theme.danger
        default: return Theme.textLo
        }
    }
}

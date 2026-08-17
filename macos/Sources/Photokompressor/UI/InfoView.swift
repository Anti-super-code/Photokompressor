import SwiftUI
import AppKit

/// Direct port of OptionsWindow.xaml's InfoPanel — the About screen that
/// takes over the body and footer when the (i) button is tapped.
struct InfoView: View {
    @ObservedObject var viewModel: OptionsViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text("A simple app to save space")
                        .font(Theme.font(size: 24, .light))
                        .foregroundColor(Theme.textHi)
                        .multilineTextAlignment(.center)

                    HeartLogo()
                        .frame(width: 132, height: 122)
                        .padding(.top, 20)
                        .padding(.bottom, 22)

                    SectionLabel(text: "OPEN SOURCE")
                        .padding(.bottom, 8)

                    Text("Free and open source under the MIT licence — built on libvips and Apple's ImageIO. Nothing you compress ever leaves your computer; the app has no network access at all.")
                        .font(Theme.font(size: 12.5, .light))
                        .foregroundColor(Theme.textMid)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(width: 380)

                    HStack(spacing: 0) {
                        Button("View the source") { NSWorkspace.shared.open(OptionsViewModel.sourceURL) }
                            .buttonStyle(LinkButtonStyle())
                    }
                    .padding(.top, 6)

                    Text("Provided as is, without warranty — use it at your own risk. Compression discards image detail and strips EXIF. Keep backups of photos you can't replace.")
                        .font(Theme.font(size: 11.5, .light))
                        .foregroundColor(Theme.textLo)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(width: 380)
                        .padding(.top, 14)

                    Button("Made by antidot.gr") { NSWorkspace.shared.open(OptionsViewModel.homepageURL) }
                        .buttonStyle(LinkButtonStyle())
                        .padding(.top, 12)

                    SunkenPanel {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Right-click menu")
                                    .font(Theme.font(size: 14.5, .semibold))
                                    .foregroundColor(Theme.textHi)
                                Text(viewModel.shellHint)
                                    .font(Theme.font(size: 11.5, .light))
                                    .foregroundColor(viewModel.shellHintOverride != nil ? Theme.danger : Theme.textLo)
                            }
                            Spacer()
                            NeuToggle(isOn: Binding(
                                get: { viewModel.shellRegistered },
                                set: { newValue in
                                    viewModel.shellRegistered = newValue
                                    viewModel.toggleShellRegistration(newValue)
                                }))
                        }
                    }
                    .frame(width: 380)
                    .padding(.top, 24)
                }
            }

            VStack(spacing: 12) {
                Button("Let's kompress") {
                    withAnimation { viewModel.infoShowing = false }
                }
                .buttonStyle(AccentButtonStyle())

                Text("V.1.0 · Made in 2026")
                    .font(Theme.font(size: 11, .light))
                    .foregroundColor(Theme.textLo)
            }
            .padding(.top, 20)
        }
    }
}

/// A square stood on its corner, plus two circles whose diameters match the
/// square's side, centred on its two upper edges — one flat colour so the
/// overlaps leave no seams. Direct port of the Canvas in OptionsWindow.xaml.
private struct HeartLogo: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 100
            let color = GraphicsContext.Shading.color(Theme.danger)

            var square = Path(CGRect(x: 22 * scale, y: 22 * scale, width: 56 * scale, height: 56 * scale))
            let center = CGPoint(x: (22 + 28) * scale, y: (22 + 28) * scale)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: .pi / 4)
                .translatedBy(x: -center.x, y: -center.y)
            square = square.applying(transform)
            context.fill(square, with: color)

            let leftCircle = Path(ellipseIn: CGRect(x: 2.2 * scale, y: 2.2 * scale, width: 56 * scale, height: 56 * scale))
            context.fill(leftCircle, with: color)
            let rightCircle = Path(ellipseIn: CGRect(x: 41.8 * scale, y: 2.2 * scale, width: 56 * scale, height: 56 * scale))
            context.fill(rightCircle, with: color)
        }
    }
}

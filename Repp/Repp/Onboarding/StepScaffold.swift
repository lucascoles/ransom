import SwiftUI

/// Every intake question uses the same skeleton: a big question, an optional
/// supporting line, scrollable content, and one button pinned to the bottom.
struct StepScaffold<Content: View>: View {
    var title: String
    var subtitle: String?
    var buttonTitle: String = "Continue"
    var isButtonEnabled: Bool = true
    /// Hidden on steps that advance the moment you tap an answer.
    var showsButton: Bool = true
    var footnote: String?
    var onNext: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(ReppFont.title(28))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(ReppFont.body(15))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 22)

            ScrollView(showsIndicators: false) {
                content()
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, 24)
            }

            if showsButton {
                VStack(spacing: 8) {
                    if let footnote {
                        Text(footnote)
                            .font(ReppFont.caption(12))
                            .foregroundStyle(Palette.inkFaint)
                            .multilineTextAlignment(.center)
                    }
                    PrimaryButton(title: buttonTitle, isEnabled: isButtonEnabled, action: onNext)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .background(
                    // Keeps the button legible when content scrolls under it.
                    LinearGradient(
                        colors: [Palette.canvas.opacity(0), Palette.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .allowsHitTesting(false),
                    alignment: .bottom
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Single-select steps advance on their own — one tap, one screen, no Continue.
enum AutoAdvance {
    static func after(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

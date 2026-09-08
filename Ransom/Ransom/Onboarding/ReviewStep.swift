import StoreKit
import SwiftUI

/// The ratings ask, placed at the end of intake.
///
/// **On the placement.** This sits immediately before the paywall, which is the
/// standard growth position and a defensible one here: by this point the user has
/// done a real rep on `FirstRepStep` and watched their own plan get built, so
/// there is something to rate. It is still earlier than ideal. The strongest ask
/// is after somebody has actually paid a toll and got their apps back, because
/// that is the moment the product has kept its promise. Worth moving if the
/// ratings that arrive are mediocre.
///
/// **On what this deliberately does not do.** There is a well-known pattern of
/// asking "enjoying the app?" first and only showing the real sheet to people who
/// say yes. It is not built here. Apple's guidance is that the system API is the
/// way to ask, and filtering by sentiment beforehand is the thing it exists to
/// replace; it also means the rating stops describing the app and starts
/// describing the filter. One honest ask, one clear way past it.
///
/// **On what the button can promise.** `requestReview` is a request, not a
/// command. iOS decides whether to show anything, and allows at most three
/// prompts per user per year across the whole app. So nothing here can wait for
/// a result or react to one: the copy avoids saying a sheet will appear, and the
/// flow advances either way.
struct ReviewStep: View {
    var onNext: () -> Void

    @Environment(\.requestReview) private var requestReview

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            RexScene(
                pose: .cheer,
                line: "You built the whole plan. If it looks like something you'd stick to, say so where it counts.",
                size: 130,
                typewriter: true
            )
            .padding(.horizontal, Metrics.screenPadding)

            VStack(spacing: 10) {
                Text("Put in a word for Rex?")
                    .font(RansomFont.title(27))
                    .foregroundStyle(Palette.ink)
                Text("Ratings are how people find Ransom. It takes a few seconds and Rex will not bring it up again.")
                    .font(RansomFont.body(15))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(.top, 32)

            Spacer()

            VStack(spacing: 8) {
                PrimaryButton(title: "Rate Ransom") {
                    requestReview()
                    // Not waiting on the sheet on purpose. iOS may show nothing
                    // at all - the yearly limit may already be spent - and a
                    // screen that sat there waiting for a dialog that is never
                    // coming would strand the user one step from the paywall.
                    onNext()
                }
                TextButton(title: "Not now", action: onNext)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 24)
        }
    }
}

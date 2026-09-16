import SwiftUI

/// A shallow dome — the top edge of a hill. Drawn as a real curve across the full
/// width rather than a scaled ellipse, so it has no side edges to clip and reads as
/// a horizon instead of as a band.
///
/// `crest` is how far down its own rect the hilltop sits (0 = at the top), and
/// `lift` how far the curve rises above that at its peak, both as fractions of the
/// rect's height. `peak` slides the summit left or right.
struct Hill: Shape {
    var crest: CGFloat = 0.45
    var lift: CGFloat = 0.38
    var peak: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        let y = rect.minY + rect.height * crest
        // A quadratic's apex reaches only halfway to its control point, so the
        // control is placed at twice the lift to land the summit where asked.
        let control = CGPoint(
            x: rect.minX + rect.width * peak,
            y: y - rect.height * lift * 2
        )
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: y), control: control)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The ground at the top of a tab — whatever the tab puts above its first card,
/// standing on a horizon that runs the full width and dissolves into the page.
///
/// The decoration is bounded on purpose: it bleeds to the screen edges so it reads
/// as a scene rather than as a card, but it stops above the first card so it never
/// competes with one. Two hills at different depths rather than one band, and a
/// mask that fades the ground out at the bottom — a hard line there is what made an
/// earlier attempt read as a stripe instead of as land.
///
/// A sun was tried twice and dropped. In the corner it was a smudge behind the
/// headline; on the horizon, where it would have read as rising, the speech bubble
/// already occupies the only place it fits.
struct HomeMasthead<Content: View>: View {
    /// How far above the plate's bottom edge the near hill crests. Tuned against
    /// the rendered clip so it lands on Rex's feet.
    var groundLine: CGFloat = 26

    @ViewBuilder var content: Content

    /// The plate runs the full width of the screen while its text stays on the
    /// usual margin, so the caller hands over un-inset content and the inset is put
    /// back here. Doing it the other way — insetting the content and stretching the
    /// background with negative padding — silently cuts the ground off 24pt short
    /// at each edge, because negative padding shrinks the frame that `.clipped()`
    /// then clips to.
    var body: some View {
        content
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, groundLine)
            .background(alignment: .bottom) {
                decoration.allowsHitTesting(false)
            }
    }

    private var decoration: some View {
        ZStack(alignment: .bottom) {
            // Far hill: higher, paler, summit pushed right so the two curves read
            // as separate land rather than as one thick stripe.
            Hill(crest: 0.34, lift: 0.30, peak: 0.72)
                .fill(Palette.sandFar)
                .frame(height: groundLine * 2.6)

            // Near ground: crests at Rex's feet and runs off the bottom.
            Hill(crest: 0.5, lift: 0.22, peak: 0.28)
                .fill(Palette.sandNear)
                .frame(height: groundLine * 2)
        }
        // The plate ends where the cards begin, so the ground dissolves into the
        // page over its last stretch instead of stopping at a hard line.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

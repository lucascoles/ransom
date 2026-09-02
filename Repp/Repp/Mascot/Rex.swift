import SwiftUI

// MARK: - Pose

/// Rex's expressions. A pose is just a bag of numbers, so SwiftUI interpolates
/// between any two of them and every transition is animatable for free.
enum RexPose: Equatable {
    case idle
    case cheer
    case coach
    case flex
    case blocked
    case sad
    case sleep
    case pushUp(down: Bool)

    var params: RexParams {
        switch self {
        case .idle:
            return RexParams()
        case .cheer:
            return RexParams(
                bodyY: -10, bodyScale: 1.04,
                armLeft: -155, armRight: 155,
                mouthCurve: 1.0, mouthOpen: 0.55,
                browAngle: -6, browY: -4,
                eyeSquint: 0.35, tailAngle: 18
            )
        case .coach:
            return RexParams(
                bodyRotation: -3,
                armLeft: -20, armRight: 118,
                mouthCurve: 0.6, mouthOpen: 0.3,
                browAngle: 8, browY: 0,
                pupilX: 4, tailAngle: -8
            )
        case .flex:
            return RexParams(
                bodyScale: 1.03,
                armLeft: -95, armRight: 95,
                armBend: 0.9,
                mouthCurve: 0.5, mouthOpen: 0.15,
                browAngle: 14, browY: 2,
                eyeSquint: 0.3, tailAngle: 10
            )
        case .blocked:
            return RexParams(
                bodyRotation: 0,
                armLeft: -78, armRight: 78,
                mouthCurve: -0.15, mouthOpen: 0.1,
                browAngle: 20, browY: 5,
                eyeSquint: 0.15, tailAngle: -14
            )
        case .sad:
            return RexParams(
                bodyY: 8, bodyScale: 0.97,
                armLeft: 14, armRight: -14,
                mouthCurve: -0.8, mouthOpen: 0.1,
                browAngle: -18, browY: 4,
                pupilY: 4, tailAngle: -22, tailDroop: 0.7
            )
        case .sleep:
            return RexParams(
                bodyY: 10, bodyScale: 0.98, bodyRotation: -4,
                armLeft: 10, armRight: -10,
                mouthCurve: 0.2, mouthOpen: 0.25,
                eyeOpen: 0.06, tailAngle: -10, tailDroop: 0.4
            )
        case .pushUp(let down):
            return RexParams(
                bodyY: down ? 26 : 2,
                bodyScale: down ? 1.02 : 1.0,
                bodyRotation: 0,
                armLeft: down ? -48 : -18,
                armRight: down ? 48 : 18,
                armBend: down ? 1.0 : 0.15,
                mouthCurve: down ? -0.2 : 0.35,
                mouthOpen: down ? 0.45 : 0.2,
                browAngle: 16, browY: 3,
                eyeSquint: down ? 0.5 : 0.15,
                tailAngle: down ? -6 : 12
            )
        }
    }
}

/// Every animatable dimension of the character.
struct RexParams: Equatable {
    var bodyY: CGFloat = 0
    var bodyScale: CGFloat = 1
    var bodyRotation: Double = 0
    /// Arm rotation in degrees, measured from hanging straight down.
    var armLeft: Double = -12
    var armRight: Double = 12
    /// 0 = straight arm, 1 = fully bent (forearm tucked in).
    var armBend: CGFloat = 0
    /// -1 frown → +1 grin.
    var mouthCurve: CGFloat = 0.7
    var mouthOpen: CGFloat = 0.2
    var browAngle: Double = 0
    var browY: CGFloat = 0
    /// 1 = wide open, 0 = shut.
    var eyeOpen: CGFloat = 1
    /// Flattens the top of the eye for a determined look.
    var eyeSquint: CGFloat = 0
    var pupilX: CGFloat = 0
    var pupilY: CGFloat = 0
    var tailAngle: Double = 0
    var tailDroop: CGFloat = 0
}

// MARK: - Rex

/// Rex — a lime gecko who happens to be very good at push-ups, and who stands
/// between you and Instagram. Drawn in vectors so he stays crisp at any size and
/// every limb can be animated independently.
struct RexView: View {
    var pose: RexPose = .idle
    var size: CGFloat = 200
    /// Idle breathing + blinking. Turn off inside lists or when Rex is decorative.
    var isAlive: Bool = true

    @State private var breathe = false
    @State private var blinkClosed = false
    @State private var tailWag = false

    /// The character is authored in this box and scaled to whatever the caller wants.
    private let designSize = CGSize(width: 240, height: 260)

    private var p: RexParams { pose.params }

    var body: some View {
        ZStack {
            tail
            legs
            arm(side: -1)
            arm(side: 1)
            bodyAndHead
        }
        .frame(width: designSize.width, height: designSize.height)
        .scaleEffect(size / designSize.width)
        .frame(width: size, height: size * (designSize.height / designSize.width))
        .animation(.spring(response: 0.42, dampingFraction: 0.62), value: pose)
        .onAppear {
            guard isAlive else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                tailWag = true
            }
            scheduleBlink()
        }
    }

    // MARK: Silhouette

    private var bodyAndHead: some View {
        ZStack {
            crest
            // Main blob: head and body read as one friendly shape.
            RexBlob()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x7BE05A), Color(hex: 0x36B84B)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(RexBlob().stroke(Color(hex: 0x1E7A34), lineWidth: 3))
                .frame(width: 176, height: 158)

            // Belly patch
            Ellipse()
                .fill(Color(hex: 0xE8FBBF))
                .frame(width: 96, height: 82)
                .offset(y: 30)
                .mask { RexBlob().frame(width: 176, height: 158) }

            face
        }
        .scaleEffect(
            x: p.bodyScale * (breathe && isAlive ? 1.012 : 1),
            y: p.bodyScale * (breathe && isAlive ? 0.988 : 1),
            anchor: .bottom
        )
        .rotationEffect(.degrees(p.bodyRotation), anchor: .bottom)
        .offset(y: p.bodyY - 18)
    }

    private var crest: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Triangle()
                    .fill(Color(hex: 0xC6F24E))
                    .overlay(Triangle().stroke(Color(hex: 0x1E7A34), lineWidth: 2.5))
                    .frame(width: 20, height: index == 1 ? 26 : 19)
            }
        }
        .offset(y: -88)
    }

    private var face: some View {
        ZStack {
            // Eyes
            HStack(spacing: 18) {
                eye(side: -1)
                eye(side: 1)
            }
            .offset(y: -34)

            // Brows
            HStack(spacing: 30) {
                brow(side: -1)
                brow(side: 1)
            }
            .offset(y: -64 + p.browY)

            // Cheeks
            HStack(spacing: 92) {
                cheek
                cheek
            }
            .offset(y: 6)

            // Nostrils — two dots keep him a lizard rather than a generic blob.
            HStack(spacing: 16) {
                Circle().fill(Color(hex: 0x1E7A34).opacity(0.55)).frame(width: 5, height: 5)
                Circle().fill(Color(hex: 0x1E7A34).opacity(0.55)).frame(width: 5, height: 5)
            }
            .offset(y: -4)

            MouthShape(curve: p.mouthCurve, openness: p.mouthOpen)
                .fill(Color(hex: 0x1B3A20))
                .frame(width: 62, height: 34)
                .offset(y: 22)

            if case .sleep = pose {
                sleepZs
            }
        }
    }

    private func eye(side: CGFloat) -> some View {
        let open: CGFloat = blinkClosed && isAlive ? 0.08 : p.eyeOpen
        return ZStack {
            Ellipse()
                .fill(.white)
                .frame(width: 46, height: 48)
                .overlay(alignment: .top) {
                    // Squint: a lid of skin drops over the top of the eye.
                    Rectangle()
                        .fill(Color(hex: 0x5FD055))
                        .frame(height: 48 * max(p.eyeSquint, 0))
                }
                .clipShape(Ellipse())
                .overlay(Ellipse().stroke(Color(hex: 0x1E7A34), lineWidth: 2.5))

            // Pupil
            Circle()
                .fill(Color(hex: 0x14210F))
                .frame(width: 20, height: 20)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .offset(x: -1, y: 2)
                }
                .offset(x: p.pupilX * side * 0.4 + p.pupilX, y: p.pupilY)
        }
        .scaleEffect(y: max(0.06, open), anchor: .center)
        .animation(.easeInOut(duration: 0.11), value: blinkClosed)
    }

    private func brow(side: CGFloat) -> some View {
        Capsule()
            .fill(Color(hex: 0x1E7A34))
            .frame(width: 26, height: 6)
            .rotationEffect(.degrees(p.browAngle * side))
            .opacity(p.eyeOpen < 0.2 ? 0.5 : 1)
    }

    private var cheek: some View {
        Ellipse()
            .fill(Color(hex: 0xFF8A6B).opacity(0.45))
            .frame(width: 24, height: 15)
    }

    private var sleepZs: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("z").font(ReppFont.display(14))
            Text("z").font(ReppFont.display(18)).offset(x: 8)
            Text("Z").font(ReppFont.display(24)).offset(x: 18)
        }
        .foregroundStyle(Palette.inkSoft)
        .offset(x: 96, y: -58)
    }

    // MARK: Limbs

    private func arm(side: CGFloat) -> some View {
        let angle = side < 0 ? p.armLeft : p.armRight
        return ZStack(alignment: .top) {
            Capsule()
                .fill(Color(hex: 0x4FCB55))
                .overlay(Capsule().stroke(Color(hex: 0x1E7A34), lineWidth: 2.5))
                .frame(width: 24, height: 62 - 22 * p.armBend)

            // Hand
            Circle()
                .fill(Color(hex: 0x5FD055))
                .overlay(Circle().stroke(Color(hex: 0x1E7A34), lineWidth: 2.5))
                .frame(width: 28, height: 28)
                .offset(y: 44 - 22 * p.armBend)
        }
        .frame(width: 28, height: 74, alignment: .top)
        // Negated: a pose reads left-arm angles as "swing outward", but a positive
        // rotation is clockwise on screen, which would tuck both arms behind the
        // body instead. Without this, every raised-arm pose loses its arms.
        .rotationEffect(.degrees(-angle), anchor: .top)
        .offset(x: 68 * side, y: p.bodyY - 24)
    }

    private var legs: some View {
        HStack(spacing: 46) {
            foot
            foot
        }
        .offset(y: 84)
    }

    private var foot: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color(hex: 0x4FCB55))
                .overlay(Capsule().stroke(Color(hex: 0x1E7A34), lineWidth: 2.5))
                .frame(width: 26, height: 34)
            Ellipse()
                .fill(Color(hex: 0x5FD055))
                .overlay(Ellipse().stroke(Color(hex: 0x1E7A34), lineWidth: 2.5))
                .frame(width: 40, height: 20)
                .offset(y: 4)
        }
    }

    private var tail: some View {
        TailShape()
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0x5FD055), Color(hex: 0xC6F24E)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(TailShape().stroke(Color(hex: 0x1E7A34), lineWidth: 2.5))
            .frame(width: 110, height: 86)
            .rotationEffect(
                .degrees(p.tailAngle + Double(tailWag && isAlive ? 7 : -7) * (1 - Double(p.tailDroop))),
                anchor: .topLeading
            )
            .offset(x: 52, y: 34)
    }

    // MARK: Blinking

    private func scheduleBlink() {
        let delay = Double.random(in: 2.4...5.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isAlive else { return }
            blinkClosed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                blinkClosed = false
                scheduleBlink()
            }
        }
    }
}

// MARK: - Shapes

/// The head/body silhouette: a wide egg with a softly squared jaw.
private struct RexBlob: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.46),
            control1: CGPoint(x: w * 0.86, y: 0),
            control2: CGPoint(x: w, y: h * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w, y: h * 0.82),
            control2: CGPoint(x: w * 0.82, y: h)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.46),
            control1: CGPoint(x: w * 0.18, y: h),
            control2: CGPoint(x: 0, y: h * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: 0, y: h * 0.18),
            control2: CGPoint(x: w * 0.14, y: 0)
        )
        path.closeSubpath()
        return path
    }
}

/// A tapering tail that curls away from the body.
private struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * 0.18))
        path.addCurve(
            to: CGPoint(x: w * 0.96, y: h * 0.9),
            control1: CGPoint(x: w * 0.62, y: h * 0.02),
            control2: CGPoint(x: w * 1.02, y: h * 0.38)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.52),
            control1: CGPoint(x: w * 0.72, y: h * 1.02),
            control2: CGPoint(x: w * 0.34, y: h * 0.86)
        )
        path.closeSubpath()
        return path
    }
}

/// A mouth that morphs from a frown through a line to an open grin.
private struct MouthShape: Shape {
    var curve: CGFloat
    var openness: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(curve, openness) }
        set { curve = newValue.first; openness = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let lift = curve * h * 0.55
        let drop = max(openness, 0.02) * h

        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * 0.3))
        // Upper lip
        path.addQuadCurve(
            to: CGPoint(x: w, y: h * 0.3),
            control: CGPoint(x: w * 0.5, y: h * 0.3 + lift)
        )
        // Lower lip
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.3),
            control: CGPoint(x: w * 0.5, y: h * 0.3 + lift + drop)
        )
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Rex poses") {
    ScrollView {
        VStack(spacing: 32) {
            ForEach(
                [RexPose.idle, .cheer, .coach, .flex, .blocked, .sad, .sleep, .pushUp(down: false), .pushUp(down: true)],
                id: \.self
            ) { pose in
                RexView(pose: pose, size: 160)
            }
        }
        .padding(40)
    }
    .reppScreenBackground()
}

extension RexPose: Hashable {}

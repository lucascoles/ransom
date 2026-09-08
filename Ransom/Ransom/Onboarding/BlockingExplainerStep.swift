import SwiftUI

// MARK: - Blocking explainer

/// What happens to the apps they named, drawn, with the Screen Time ask on the
/// same screen.
///
/// The Family Controls prompt is the scariest sheet in the flow: Apple's copy,
/// Apple's wording, a passcode. Asked cold it reads as the app wanting into the
/// phone. Asked underneath a picture of their own apps behind padlocks, with Rex
/// in the middle and three plain sentences about what a lock means here, it
/// reads as the obvious next step. That is the whole reason this screen exists.
///
/// **No third-party marks.** Apple only renders another app's real icon through
/// `Label(ApplicationToken)`, and a token exists only for apps already chosen in
/// `FamilyActivityPicker`, which needs the permission this screen is about to
/// ask for. So the tiles are the emoji stand-ins and plain names the apps step
/// already uses (nominative use, the low-risk end per COPY-NOTES.md), drawn in
/// Ransom's own chrome with a padlock badge. No logo is bundled, and the tiles
/// are the user's own picks, so the picture is theirs rather than a stock grid.
///
/// Skippable in one tap. Home carries the same ask, so refusing here loses
/// nothing but the moment.
struct BlockingExplainerStep: View {
    var profile: UserProfile
    var onNext: () -> Void

    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isRequesting = false
    @State private var locked = false

    private var plan: RansomPlan { RansomPlan.make(from: profile) }

    /// Their picks, in the order the apps step lists them.
    private var apps: [DistractingApp] {
        DistractingApp.allCases.filter { profile.distractingApps.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    AppLockGrid(apps: apps, locked: locked)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your apps get a doorman")
                            .font(RansomFont.title(28))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Nothing is deleted. Rex stands at the door and asks for a set first.")
                            .font(RansomFont.body(15))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        row(icon: "hand.tap.fill",
                            title: "You pick the apps.",
                            detail: "Nothing else on your phone is touched.")
                        row(icon: plan.exercise.symbol,
                            title: "Your reps open them.",
                            detail: "\(plan.setTarget) \(plan.exercise.title.lowercased()) banks \(plan.minutesPerUnlock) minutes. Spend them on any app you locked.")
                        row(icon: "lock.open.fill",
                            title: "There is always a way in.",
                            detail: "Opening a locked app spends from your bank. When the bank is empty, Rex is back at the door.")
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 24)
            }

            footer
        }
        .onAppear {
            guard !reduceMotion else {
                locked = true
                return
            }
            // The apps arrive open, then lock. Seeing the padlocks land is the
            // one-second version of everything the three rows say.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    locked = true
                }
                Haptics.select()
            }
        }
    }

    // MARK: Pieces

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ExerciseIcon(name: icon, size: 16)
                .foregroundStyle(Palette.brand)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Palette.brandSoft))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            if screenTime.isAuthorized {
                // Already granted (a re-run of intake, or Settings got there
                // first). Nothing to ask, so nothing is pretended.
                PrimaryButton(title: "Continue", action: onNext)
            } else {
                Text("Apple asks for this one. Which apps you lock never leaves your phone.")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Allow Screen Time", icon: "lock.fill", isLoading: isRequesting) {
                    isRequesting = true
                    Task {
                        await screenTime.requestAuthorization()
                        if screenTime.isAuthorized {
                            screenTime.startMonitoring()
                        }
                        isRequesting = false
                        onNext()
                    }
                }

                // No scolding on the way past. Home asks again, with the same
                // picture, when they get there.
                TextButton(title: "Not now", action: onNext)
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
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

// MARK: - The grid

/// A three-by-three of app tiles with Rex in the middle, each tile taking a
/// padlock when `locked` flips.
///
/// The tiles are the apps the user named, so the picture is about their phone.
/// Anyone who only picked "Something else" gets three generic categories, drawn
/// the same way, so the screen still shows the mechanic rather than a hole. The
/// last tile is always "Any app": the real list is chosen later in Apple's
/// picker, which covers everything on the phone, and this says so.
private struct AppLockGrid: View {
    var apps: [DistractingApp]
    var locked: Bool

    private struct Tile: Identifiable {
        let id: String
        let emoji: String?
        let symbol: String?
        let title: String
    }

    private static let cellSize: CGFloat = 66
    private static let columns = 3

    private var tiles: [Tile] {
        var tiles = apps.prefix(7).map {
            Tile(id: $0.id, emoji: $0.emoji, symbol: nil, title: $0.title)
        }
        if tiles.isEmpty {
            tiles = [
                Tile(id: "social", emoji: nil, symbol: "bubble.left.and.bubble.right.fill", title: "Social"),
                Tile(id: "video", emoji: nil, symbol: "play.rectangle.fill", title: "Video"),
                Tile(id: "games", emoji: nil, symbol: "gamecontroller.fill", title: "Games"),
            ]
        }
        tiles.append(Tile(id: "any", emoji: nil, symbol: "plus", title: "Any app"))
        return tiles
    }

    /// Nine cells. The centre is Rex; the rest fill from the top left and stay
    /// empty past the last tile, so four picks read as four picks rather than
    /// four picks and five gaps of something.
    private var cells: [Tile?] {
        var cells: [Tile?] = Array(repeating: nil, count: Self.columns * Self.columns)
        let centre = cells.count / 2
        var next = 0
        for tile in tiles {
            if next == centre { next += 1 }
            guard next < cells.count else { break }
            cells[next] = tile
            next += 1
        }
        // Only the rows in use. Four picks and Rex fill two rows; a reserved
        // third row of nothing pushed the headline halfway down the screen.
        let used = max(next, centre + 1)
        let rows = Int((Double(used) / Double(Self.columns)).rounded(.up))
        return Array(cells.prefix(rows * Self.columns))
    }

    var body: some View {
        let cells = cells
        // Rex sits in the middle cell of the full three-by-three, which is the
        // last cell of the second row's centre whatever the row count is.
        let centre = (Self.columns * Self.columns) / 2

        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(Self.cellSize + 22), spacing: 6), count: Self.columns),
            spacing: 10
        ) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, tile in
                if index == centre {
                    rex
                } else if let tile {
                    tileView(tile, order: index)
                } else {
                    Color.clear.frame(width: Self.cellSize, height: Self.cellSize + 20)
                }
            }
        }
    }

    private var rex: some View {
        VStack(spacing: 0) {
            RexImage(pose: .coach, size: Self.cellSize * 0.82, isAlive: false)
            Spacer(minLength: 0)
        }
        .frame(height: Self.cellSize + 20)
        .accessibilityLabel("Rex, the doorman")
    }

    private func tileView(_ tile: Tile, order: Int) -> some View {
        let isAny = tile.id == "any"
        return VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(isAny ? Palette.surfaceAlt : Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
                    .overlay {
                        if let emoji = tile.emoji {
                            Text(emoji).font(.system(size: 30))
                        } else if let symbol = tile.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: isAny ? 22 : 26, weight: .semibold))
                                .foregroundStyle(isAny ? Palette.inkFaint : Palette.brand)
                        }
                    }
                    .frame(width: Self.cellSize, height: Self.cellSize)

                if !isAny {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Palette.brand))
                        .overlay(Circle().strokeBorder(Palette.canvas, lineWidth: 2))
                        .offset(x: 7, y: 7)
                        .scaleEffect(locked ? 1 : 0.01)
                        .opacity(locked ? 1 : 0)
                        // Staggered by cell, so the locks land one after another
                        // rather than as a single click.
                        .animation(.spring(response: 0.38, dampingFraction: 0.6)
                            .delay(Double(order) * 0.05), value: locked)
                }
            }
            .frame(width: Self.cellSize, height: Self.cellSize)

            Text(tile.title)
                .font(RansomFont.caption(11))
                .foregroundStyle(isAny ? Palette.inkFaint : Palette.inkSoft)
                .lineLimit(1)
        }
        .frame(height: Self.cellSize + 20, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAny ? "Any app you choose" : "\(tile.title), locked")
    }
}

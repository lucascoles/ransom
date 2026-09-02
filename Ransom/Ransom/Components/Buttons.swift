import SwiftUI

/// The one loud button. There is never more than one on screen.
struct PrimaryButton: View {
    var title: String
    var icon: String?
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            guard isEnabled, !isLoading else { return }
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Palette.onGreen)
                } else {
                    if let icon {
                        Image(systemName: icon).font(.system(size: 17, weight: .bold))
                    }
                    Text(title).font(RansomFont.headline(17))
                }
            }
            .foregroundStyle(Palette.onGreen)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(Palette.green)
            )
            .opacity(isEnabled ? 1 : 0.35)
            .shadow(color: Palette.green.opacity(isEnabled ? 0.3 : 0), radius: 14, y: 6)
        }
        .pressable()
        .disabled(!isEnabled || isLoading)
    }
}

/// Quiet secondary action — outlined, never competes with the primary.
struct SecondaryButton: View {
    var title: String
    var icon: String?
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)) }
                Text(title).font(RansomFont.headline(16))
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(Palette.surfaceAlt)
            )
        }
        .pressable()
    }
}

/// Text-only action for "Skip", "Restore purchases", "Maybe later".
struct TextButton: View {
    var title: String
    var tint: Color = Palette.inkSoft
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(RansomFont.caption(14))
                .foregroundStyle(tint)
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
        }
        .pressable(scale: 0.94)
    }
}

/// Small rounded label used for streaks, badges and inline metadata.
struct Pill: View {
    var text: String
    var icon: String?
    var tint: Color = Palette.green
    var background: Color = Palette.greenSoft

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
            Text(text).font(RansomFont.caption(12))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(background))
    }
}

import SwiftUI

/// An icon named either by SF Symbols or by the asset catalog.
///
/// Everything in the app names its icons with a string, which is convenient right
/// up to the point where SF Symbols has no glyph for the thing you are drawing.
/// It has no push-up: `figure.strengthtraining.functional` is a lunge,
/// `figure.core.training` is a sit-up, and the rest of the fitness set is further
/// away still. So `Exercise.pushUps` names a glyph Apple does not ship and this
/// resolves it from the asset catalog instead.
///
/// The two kinds cannot be drawn the same way, which is the whole reason this is a
/// view rather than an `Image` initialiser. A symbol is glyph and takes its size
/// from the font; a bundled asset is a picture and ignores the font entirely, so
/// sizing one the way you size the other gets you either a push-up the height of
/// the button or an invisible one. Each branch is sized in its own terms and both
/// end up occupying the same square.
///
/// Bundled art wins over a system symbol of the same name deliberately: if Apple
/// ever ships `figure.pushup`, deleting the imageset is the entire migration.
struct ExerciseIcon: View {
    let name: String
    var size: CGFloat
    var weight: Font.Weight = .semibold

    private var hasBundledArt: Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return false
        #endif
    }

    var body: some View {
        if hasBundledArt {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
                .font(.system(size: size, weight: weight))
        }
    }
}

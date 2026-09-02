import Foundation

/// Rex's expressions.
///
/// The vocabulary the whole app speaks to the character in. It outlived the
/// vector drawing that originally implemented it — `RexImage` now maps these
/// onto artwork, and the sprite set will map them one-to-one onto files.
enum RexPose: Hashable {
    case idle
    case cheer
    case coach
    case flex
    case blocked
    case sad
    case sleep
    case pushUp(down: Bool)
}

// Composites the real figure asset with the brain glyph at the coordinates
// LevelsCard uses, to check it lands in the skull before it goes near a phone.
import AppKit
import SwiftUI

let repo = NSString(string: "~/ransom/Ransom/Ransom/Resources/Assets.xcassets").expandingTildeInPath
func layer(_ name: String, _ file: String) -> NSImage? {
    NSImage(contentsOfFile: "\(repo)/\(name).imageset/\(file)@3x.png")
}

struct Figure: View {
    static let aspect: CGFloat = 326.0 / 900.0
    static let headCentreY: CGFloat = 48.0 / 900.0
    static let brainSpan: CGFloat = 52.0 / 326.0
    var height: CGFloat
    var tint: Color
    var showBox: Bool

    var body: some View {
        let w = height * Self.aspect
        let span = w * Self.brainSpan
        ZStack {
            if let skin = layer("LevelFigureSkin", "skin") {
                Image(nsImage: skin).resizable().scaledToFit()
                    .foregroundStyle(Color(red: 0.84, green: 0.85, blue: 0.83))
            }
            if let outline = layer("LevelFigureOutline", "outline") {
                Image(nsImage: outline).resizable().scaledToFit()
                    .foregroundStyle(Color(red: 0.10, green: 0.11, blue: 0.10))
            }
            Image(systemName: "brain")
                .resizable().scaledToFit()
                .foregroundStyle(tint)
                .frame(width: span, height: span)
                .overlay { if showBox { Rectangle().stroke(.blue.opacity(0.6), lineWidth: 0.5) } }
                .position(x: w / 2, y: height * Self.headCentreY)
        }
        .frame(width: w, height: height)
    }
}

struct Sheet: View {
    var body: some View {
        HStack(spacing: 28) {
            Figure(height: 310, tint: Color(red: 0.18, green: 0.62, blue: 0.31), showBox: false)
            Figure(height: 310, tint: Color(red: 0.94, green: 0.38, blue: 0.15), showBox: false)
            Figure(height: 310, tint: Color(red: 0.89, green: 0.24, blue: 0.24), showBox: true)
            // Head at 3x, to see the fit
            Figure(height: 930, tint: Color(red: 0.89, green: 0.24, blue: 0.24), showBox: true)
                .frame(width: 930 * Figure.aspect, height: 310, alignment: .top)
                .clipped()
        }
        .padding(24)
        .background(Color(red: 0.96, green: 0.95, blue: 0.92))
    }
}

MainActor.assumeIsolated {
    let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "head.png"
    let r = ImageRenderer(content: Sheet())
    r.scale = 3
    if let img = r.nsImage, let tiff = img.tiffRepresentation,
       let bm = NSBitmapImageRep(data: tiff), let png = bm.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    } else { print("failed") }
}

// Replays a screen recording of Ransom's camera set through the same Vision
// request the app uses, and prints what the detector would have seen.
//
// The recording shows the preview layer, which is `.resizeAspectFill` of a
// 9:16 buffer into a 3:4 window: full width, middle 75% of the height. So the
// window is cropped back out and letterboxed to 9:16 before Vision sees it,
// which puts every joint at the same normalised position the app measured.
//
// usage: swift posedump.swift <video> <cropX> <cropY> <cropW> <cropH> [fps]

import AVFoundation
import CoreImage
import Foundation
import Vision

let args = CommandLine.arguments
guard args.count >= 6 else {
    FileHandle.standardError.write("usage: posedump <video> x y w h [fps]\n".data(using: .utf8)!)
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
let cropX = Double(args[2])!, cropY = Double(args[3])!
let cropW = Double(args[4])!, cropH = Double(args[5])!
let targetFPS = args.count > 6 ? Double(args[6])! : 30.0

let asset = AVURLAsset(url: url)
guard let track = asset.tracks(withMediaType: .video).first else { exit(3) }
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(
    track: track,
    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
)
output.alwaysCopiesSampleData = false
reader.add(output)
reader.startReading()

let ciContext = CIContext(options: [.useSoftwareRenderer: false])
// 9:16, the shape of the buffer the app was handed.
let padH = cropW / 0.5625
let frameAspect = cropW / padH

func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
    let v1 = CGPoint(x: a.x - b.x, y: a.y - b.y)
    let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
    let dot = v1.x * v2.x + v1.y * v2.y
    let m = hypot(v1.x, v1.y) * hypot(v2.x, v2.y)
    guard m > 0 else { return .nan }
    return Double(acos(max(-1, min(1, dot / m)))) * 180 / .pi
}

let lenient: Set<VNHumanBodyPoseObservation.JointName> = [.leftWrist, .rightWrist, .leftElbow, .rightElbow]
func bar(_ j: VNHumanBodyPoseObservation.JointName) -> Float { lenient.contains(j) ? 0.15 : 0.2 }

print("t,found,swidth,elbow,elbowL,elbowR,shoulderY,wristY,hipY,kneeY,ankleY,missLenient,againstEdge,confLS,confRS,confLE,confRE,confLW,confRW")

var nextEmit = 0.0
let step = 1.0 / targetFPS

while let sample = output.copyNextSampleBuffer() {
    let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
    guard t + 1e-6 >= nextEmit, let px = CMSampleBufferGetImageBuffer(sample) else { continue }
    nextEmit += step

    let full = CIImage(cvPixelBuffer: px)
    let h = full.extent.height
    // CIImage's y runs up from the bottom; the crop rect is given top-down.
    let rect = CGRect(x: cropX, y: h - cropY - cropH, width: cropW, height: cropH)
    let window = full.cropped(to: rect)
        .transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
    // Letterbox back to the buffer's shape: the window is the middle 75%.
    let inset = (padH - cropH) / 2
    let padded = window
        .transformed(by: CGAffineTransform(translationX: 0, y: inset))
        .composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: cropW, height: padH)))
        .cropped(to: CGRect(x: 0, y: 0, width: cropW, height: padH))

    guard let cg = ciContext.createCGImage(padded, from: padded.extent) else { continue }
    let request = VNDetectHumanBodyPoseRequest()
    try? VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:]).perform([request])

    guard let obs = (request.results ?? []).first else {
        print("\(String(format: "%.3f", t)),0,,,,,,,,,,,,,,,,,")
        continue
    }
    let points = (try? obs.recognizedPoints(.all)) ?? [:]

    func raw(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        guard let p = points[j], p.confidence > bar(j) else { return nil }
        return p.location
    }
    func measured(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        guard let p = raw(j) else { return nil }
        return CGPoint(x: p.x * frameAspect, y: p.y)
    }
    func conf(_ j: VNHumanBodyPoseObservation.JointName) -> String {
        points[j].map { String(format: "%.2f", $0.confidence) } ?? ""
    }
    func f(_ v: Double?) -> String { v.map { String(format: "%.3f", $0) } ?? "" }

    let ls = measured(.leftShoulder), rs = measured(.rightShoulder)
    var swidth: Double?
    if let l = ls, let r = rs { swidth = Double(hypot(l.x - r.x, l.y - r.y)) }

    var elbowL: Double?, elbowR: Double?
    if let s = ls, let e = measured(.leftElbow), let w = measured(.leftWrist) { elbowL = angle(s, e, w) }
    if let s = rs, let e = measured(.rightElbow), let w = measured(.rightWrist) { elbowR = angle(s, e, w) }
    let elbow = [elbowL, elbowR].compactMap { $0 }.min()

    let shoulderY = [ls?.y, rs?.y].compactMap { $0 }.map(Double.init)
    let wristY = [measured(.leftWrist)?.y, measured(.rightWrist)?.y].compactMap { $0 }.map(Double.init)
    let hipY = [measured(.leftHip)?.y, measured(.rightHip)?.y].compactMap { $0 }.map(Double.init)
    let kneeY = [measured(.leftKnee)?.y, measured(.rightKnee)?.y].compactMap { $0 }.map(Double.init)
    let ankleY = [measured(.leftAnkle)?.y, measured(.rightAnkle)?.y].compactMap { $0 }.map(Double.init)
    func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    let missing = lenient.filter { raw($0) == nil }.count
    let confident = points.values.filter { $0.confidence > 0.15 }.map { $0.location }
    let againstEdge = confident.contains { $0.x < 0.02 || $0.x > 0.98 || $0.y < 0.02 || $0.y > 0.98 }

    print([
        String(format: "%.3f", t), "1",
        f(swidth), f(elbow), f(elbowL), f(elbowR),
        f(mean(shoulderY)), f(mean(wristY)), f(mean(hipY)), f(mean(kneeY)), f(mean(ankleY)),
        "\(missing)", againstEdge ? "1" : "0",
        conf(.leftShoulder), conf(.rightShoulder),
        conf(.leftElbow), conf(.rightElbow),
        conf(.leftWrist), conf(.rightWrist),
    ].joined(separator: ","))
}

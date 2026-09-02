import CoreMotion
import Foundation
import Observation
import SwiftUI
import UIKit

/// Counts reps from the phone's sensors.
///
/// Each movement is read differently:
///  • Push-ups use the proximity sensor — the phone lies face-up under your chest
///    and your torso covers it at the bottom of every rep. It's the most reliable
///    signal on the device and needs no calibration.
///  • Jumping jacks and high knees use accelerometer impact peaks with a refractory
///    window, so a single landing can't register twice.
///  • Squats and sit-ups use device attitude, calibrated against whatever position
///    the phone starts in, then counting full down-and-back-up sweeps.
///
/// Every mode also accepts taps, so a rep is never lost to a bad sensor reading.
@Observable
final class RepEngine {
    enum Phase: Equatable {
        case idle
        case counting
        case finished
    }

    private(set) var reps: Int = 0
    private(set) var phase: Phase = .idle
    /// 0 = top of the rep, 1 = bottom. Drives Rex's push-up animation live.
    private(set) var depth: Double = 0
    /// Nil when things are going fine; otherwise a short nudge shown under the counter.
    private(set) var formHint: String?
    private(set) var sensorAvailable: Bool = true

    let exercise: Exercise
    let target: Int

    var isComplete: Bool { reps >= target }
    var progress: Double { target > 0 ? min(1, Double(reps) / Double(target)) : 0 }

    private let motion = CMMotionManager()
    private var lastRepAt: Date = .distantPast
    private var startedAt: Date = .now

    // Tilt-mode state
    private var baselinePitch: Double?
    private var isDown = false

    // Impact-mode state
    private var wasAboveThreshold = false

    private var proximityObserver: NSObjectProtocol?

    init(exercise: Exercise, target: Int) {
        self.exercise = exercise
        self.target = target
    }

    deinit {
        stopSensors()
    }

    var elapsedSeconds: Int { Int(Date().timeIntervalSince(startedAt)) }

    // MARK: - Lifecycle

    func start() {
        guard phase != .counting else { return }
        reps = 0
        depth = 0
        formHint = nil
        isDown = false
        baselinePitch = nil
        wasAboveThreshold = false
        startedAt = .now
        lastRepAt = .distantPast
        phase = .counting

        switch exercise.sensing {
        case .proximity: startProximity()
        case .impact:    startImpact()
        case .tilt:      startTilt()
        }
    }

    func stop() {
        stopSensors()
        phase = .finished
    }

    func cancel() {
        stopSensors()
        phase = .idle
        reps = 0
    }

    /// The always-available fallback. Also how the "tap to count" mode works.
    func registerManualRep() {
        guard phase == .counting else { return }
        commitRep(minimumGap: 0.15)
    }

    // MARK: - Proximity (push-ups)

    private func startProximity() {
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true

        guard device.isProximityMonitoringEnabled else {
            // iPads and some states have no proximity sensor — fall back to tilt,
            // which still reads a push-up as the phone rocks under your chest.
            sensorAvailable = false
            formHint = "No proximity sensor here — tap the screen for each rep."
            startTilt()
            return
        }

        formHint = "Phone on the floor, screen up, under your chest."

        proximityObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: device,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let isNear = UIDevice.current.proximityState
            withAnimation(.easeOut(duration: 0.18)) {
                self.depth = isNear ? 1 : 0
            }
            // A rep completes on the way back up, not on the way down.
            if !isNear && self.isDown {
                self.commitRep(minimumGap: 0.45)
                self.isDown = false
            } else if isNear {
                self.isDown = true
                self.formHint = nil
            }
        }
    }

    // MARK: - Impact (jumping jacks, high knees)

    private func startImpact() {
        guard motion.isDeviceMotionAvailable else {
            sensorAvailable = false
            formHint = "Motion unavailable — tap the screen for each rep."
            return
        }

        formHint = "Hold the phone or pop it in a pocket."
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }

            let acceleration = data.userAcceleration
            let magnitude = sqrt(
                acceleration.x * acceleration.x
                + acceleration.y * acceleration.y
                + acceleration.z * acceleration.z
            )

            withAnimation(.easeOut(duration: 0.12)) {
                self.depth = min(1, magnitude / 1.6)
            }

            let threshold = 0.85
            if magnitude > threshold, !self.wasAboveThreshold {
                self.wasAboveThreshold = true
                self.commitRep(minimumGap: 0.32)
            } else if magnitude < threshold * 0.55 {
                // Require the signal to settle before the next peak can count.
                self.wasAboveThreshold = false
            }
        }
    }

    // MARK: - Tilt (squats, sit-ups)

    private func startTilt() {
        guard motion.isDeviceMotionAvailable else {
            sensorAvailable = false
            formHint = "Motion unavailable — tap the screen for each rep."
            return
        }

        motion.deviceMotionUpdateInterval = 1.0 / 40.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }

            let pitch = data.attitude.pitch
            // First reading defines "standing" — no calibration screen needed.
            guard let baseline = self.baselinePitch else {
                self.baselinePitch = pitch
                return
            }

            let deviation = abs(pitch - baseline)
            withAnimation(.easeOut(duration: 0.12)) {
                self.depth = min(1, deviation / 0.9)
            }

            if deviation > 0.62, !self.isDown {
                self.isDown = true
                self.formHint = nil
            } else if deviation < 0.22, self.isDown {
                self.isDown = false
                self.commitRep(minimumGap: 0.5)
            }
        }
    }

    // MARK: - Shared

    /// Debounced so sensor noise can't inflate a count, and so nobody can shake
    /// their way through a set.
    private func commitRep(minimumGap: TimeInterval) {
        guard phase == .counting else { return }
        guard Date().timeIntervalSince(lastRepAt) > minimumGap else { return }
        lastRepAt = .now

        reps += 1
        Haptics.rep()

        if reps >= target {
            stop()
        }
    }

    private func stopSensors() {
        motion.stopDeviceMotionUpdates()
        if let proximityObserver {
            NotificationCenter.default.removeObserver(proximityObserver)
            self.proximityObserver = nil
        }
        UIDevice.current.isProximityMonitoringEnabled = false
    }
}

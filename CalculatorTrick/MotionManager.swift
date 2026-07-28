import Foundation
import CoreMotion
import Combine

/// Wraps CoreMotion to expose device tilt (for rolling the scattered buttons)
/// and shake detection (to restore the calculator), matching the real
/// gyroscope-based mechanic used by physical "crashed calculator" magic props.
final class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private var lastShakeMagnitude: Double = 1.0

    /// Roll/pitch expressed as -1...1, ready to drive an acceleration bias.
    @Published var tiltX: Double = 0
    @Published var tiltY: Double = 0

    /// Flips to true for a single run-loop tick whenever a shake is detected.
    @Published var shakeDetected = false

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }

            // Attitude gives us a stable tilt reading independent of heading.
            self.tiltX = max(-1, min(1, data.attitude.roll / (.pi / 4)))
            self.tiltY = max(-1, min(1, data.attitude.pitch / (.pi / 4)))

            // Shake detection via the magnitude of user acceleration
            // (gravity already removed by CoreMotion).
            let a = data.userAcceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            if magnitude > 2.3 {
                self.shakeDetected = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.shakeDetected = false
                }
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

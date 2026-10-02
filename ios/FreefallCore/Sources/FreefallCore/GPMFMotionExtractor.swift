import CGPMF
import Foundation

public enum GPMFMotionExtractorError: Error {
    case extractionFailed(Int32)
}

public struct GPMFMotionExtractor: Sendable {
    public init() {}

    private struct RawMotion {
        let time: Double
        let vector: MotionVector
    }

    /// Produces measured G-force plus a simple freefall-model estimate. The
    /// estimated altitude and speed are intentionally not presented as GPS data.
    public func telemetry(videoURL: URL, jumpID: String) throws -> Telemetry? {
        // GoPro's parser stores FourCC values in host-order via MAKEID.
        let accelerometer: UInt32 = 0x4c434341 // ACCL
        let gravityKey: UInt32 = 0x56415247 // GRAV
        let source = try extract(videoURL: videoURL, fourCC: accelerometer)
        let gravity = try extract(videoURL: videoURL, fourCC: gravityKey)
        guard !source.isEmpty else { return nil }
        let firstTime = source[0].time
        var samples: [TelemetrySample] = []
        samples.reserveCapacity(source.count / 20 + 1)

        // ACCL is typically around 200 Hz. Ten samples per second is sufficient
        // for the replay UI while retaining short G-force changes.
        var nextOutputTime = 0.0
        var gravityIndex = 0
        for motion in source {
            let time = max(0, motion.time - firstTime)
            guard time + 0.000_001 >= nextOutputTime else { continue }
            while gravityIndex + 1 < gravity.count,
                  gravity[gravityIndex + 1].time <= motion.time {
                gravityIndex += 1
            }
            let gravityVector = gravity.isEmpty ? nil : gravity[gravityIndex].vector
            let acceleration = motion.vector.magnitude
            let gForce = acceleration / 9.80665

            // A bounded freefall model, anchored at video start. This is useful
            // for experimenting when GPS is absent, but is not measured motion.
            let terminalSpeed = 55.0
            let timeConstant = 3.5
            let exponential = exp(-time / timeConstant)
            let verticalSpeed = -terminalSpeed * (1 - exponential)
            let distance = terminalSpeed * (time - timeConstant * (1 - exponential))
            let altitude = max(0, 4_000 - distance)
            samples.append(TelemetrySample(
                time: time,
                altitude: altitude,
                verticalSpeed: verticalSpeed,
                speed3D: abs(verticalSpeed),
                gForce: gForce,
                acceleration: motion.vector,
                gravity: gravityVector
            ))
            nextOutputTime += 0.1
        }

        guard !samples.isEmpty else { return nil }
        return Telemetry(
            jumpID: jumpID,
            timeOffset: firstTime,
            altitudeReference: "estimated_from_motion_model_helmet_zxy_v1",
            samples: samples
        )
    }

    private func extract(videoURL: URL, fourCC: UInt32) throws -> [RawMotion] {
        var result = FFMotionSamples(samples: nil, count: 0)
        let status = videoURL.path.withCString {
            FFExtractMotion($0, fourCC, &result)
        }
        guard status == 0 else { throw GPMFMotionExtractorError.extractionFailed(status) }
        defer { FFFreeMotion(result) }
        guard let pointer = result.samples, result.count > 0 else { return [] }
        let source = UnsafeBufferPointer(start: pointer, count: Int(result.count))
        return source.map {
            RawMotion(
                time: $0.time,
                // This camera declares ORIN=ZXY. Normalize the stored Z,X,Y
                // elements to canonical helmet-relative X,Y,Z axes.
                vector: MotionVector(x: $0.y, y: $0.z, z: $0.x)
            )
        }
    }
}

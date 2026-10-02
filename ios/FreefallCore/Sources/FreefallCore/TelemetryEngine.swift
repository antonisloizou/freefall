import Foundation

public struct TelemetryEngine: Sendable {
    private let samples: [TelemetrySample]
    private let timeOffset: Double
    public let maximumGap: Double

    public init(samples: [TelemetrySample], timeOffset: Double = 0, maximumGap: Double = 2) {
        // Drop invalid samples and resolve duplicate times deterministically.
        var unique: [Double: TelemetrySample] = [:]
        for sample in samples where sample.time.isFinite && sample.altitude.isFinite && sample.verticalSpeed.isFinite && sample.speed3D.isFinite {
            unique[sample.time] = sample
        }
        self.samples = unique.values.sorted { $0.time < $1.time }
        self.timeOffset = timeOffset
        self.maximumGap = maximumGap
    }

    public func at(videoTime: Double) -> TelemetrySample? {
        let t = videoTime - timeOffset
        guard t.isFinite, let first = samples.first, let last = samples.last,
              t >= first.time, t <= last.time else { return nil }
        var low = 0
        var high = samples.count - 1
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].time < t { low = mid + 1 } else { high = mid }
        }
        let right = samples[low]
        if right.time == t { return right }
        guard low > 0 else { return nil }
        let left = samples[low - 1]
        let gap = right.time - left.time
        guard gap > 0, gap <= maximumGap else { return nil }
        let fraction = (t - left.time) / gap
        func blend(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }
        let gForce: Double?
        if let leftG = left.gForce, let rightG = right.gForce {
            gForce = blend(leftG, rightG)
        } else {
            gForce = nil
        }
        func blendVector(_ left: MotionVector?, _ right: MotionVector?) -> MotionVector? {
            guard let left, let right else { return nil }
            return MotionVector(
                x: blend(left.x, right.x),
                y: blend(left.y, right.y),
                z: blend(left.z, right.z)
            )
        }
        return TelemetrySample(
            time: t,
            altitude: blend(left.altitude, right.altitude),
            verticalSpeed: blend(left.verticalSpeed, right.verticalSpeed),
            speed3D: blend(left.speed3D, right.speed3D),
            gForce: gForce,
            acceleration: blendVector(left.acceleration, right.acceleration),
            gravity: blendVector(left.gravity, right.gravity)
        )
    }
}

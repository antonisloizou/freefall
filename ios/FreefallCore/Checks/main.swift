import FreefallCore
import Foundation

func sample(_ t: Double, _ altitude: Double) -> TelemetrySample {
    .init(time: t, altitude: altitude, verticalSpeed: -50, speed3D: 52)
}

let offset = TelemetryEngine(samples: [sample(0, 4000), sample(1, 3950)], timeOffset: 10)
precondition(offset.at(videoTime: 10.5)?.altitude == 3975, "interpolation")
precondition(offset.at(videoTime: 10.5)?.time == 0.5, "video offset")
precondition(offset.at(videoTime: 9) == nil, "before source range")
precondition(offset.at(videoTime: 12) == nil, "after source range")

let gap = TelemetryEngine(samples: [sample(0, 4000), sample(10, 3500)])
precondition(gap.at(videoTime: 5) == nil, "missing data must not be invented")
precondition(gap.at(videoTime: 10)?.altitude == 3500, "exact sample after gap")

let invalid = TelemetryEngine(samples: [sample(1, 3950), sample(0, 4000), sample(1, 3900), sample(2, .nan)])
precondition(invalid.at(videoTime: 0.5)?.altitude == 3950, "ordering and duplicate times")
precondition(invalid.at(videoTime: .nan) == nil, "invalid replay time")
precondition(invalid.at(videoTime: 2) == nil, "invalid sample")
precondition(TelemetryEngine(samples: []).at(videoTime: 0) == nil, "empty source")

let measured = TelemetryEngine(samples: [
    .init(time: 0, altitude: 4_000, verticalSpeed: -40, speed3D: 42, gForce: 0.5,
          acceleration: .init(x: 0, y: 1, z: 2), gravity: .init(x: 0, y: 1, z: 0)),
    .init(time: 1, altitude: 3_950, verticalSpeed: -50, speed3D: 52, gForce: 1.5,
          acceleration: .init(x: 2, y: 3, z: 4), gravity: .init(x: 0, y: 0, z: 1))
])
precondition(measured.at(videoTime: 0.5)?.gForce == 1.0, "G-force interpolation")
precondition(measured.at(videoTime: 0.5)?.acceleration == .init(x: 1, y: 2, z: 3), "vector interpolation")

print("Passed 12 telemetry checks, including synchronized vector interpolation.")

if CommandLine.arguments.count > 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let telemetry = try GPMFMotionExtractor().telemetry(videoURL: url, jumpID: "check")
    precondition(telemetry?.samples.isEmpty == false, "expected GPMF accelerometer samples")
    precondition(telemetry?.samples.first?.acceleration != nil, "expected acceleration vector")
    precondition(telemetry?.samples.first?.gravity != nil, "expected gravity vector")
    print("Extracted \(telemetry?.samples.count ?? 0) replay samples from \(url.lastPathComponent).")
}

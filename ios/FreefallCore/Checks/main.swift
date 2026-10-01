import FreefallCore

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

print("Passed 10 telemetry checks: interpolation, offsets, gaps, ordering, duplicates, invalid values, empty sources.")

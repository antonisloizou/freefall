import Foundation

public struct JumpEvent: Codable, Sendable {
    public let kind: String
    public let time: Double
}

public struct Jump: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let location: String
    public let recordedAt: String
    public let visibility: String
    public let demo: Bool
    public let videoURL: URL?
    public let duration: Double
    public let events: [JumpEvent]

    public var freefallDuration: Double? {
        guard let exit = events.first(where: { $0.kind == "exit" }),
              let deployment = events.first(where: { $0.kind == "deployment" }),
              deployment.time >= exit.time else { return nil }
        return deployment.time - exit.time
    }
}

public struct TelemetrySample: Codable, Sendable, Equatable {
    public let time: Double
    public let altitude: Double
    public let verticalSpeed: Double
    public let speed3D: Double

    public init(time: Double, altitude: Double, verticalSpeed: Double, speed3D: Double) {
        self.time = time
        self.altitude = altitude
        self.verticalSpeed = verticalSpeed
        self.speed3D = speed3D
    }
}

public struct Telemetry: Codable, Sendable {
    public let jumpID: String
    /// videoTime = sampleTime + timeOffset
    public let timeOffset: Double
    public let altitudeReference: String
    public let samples: [TelemetrySample]
}

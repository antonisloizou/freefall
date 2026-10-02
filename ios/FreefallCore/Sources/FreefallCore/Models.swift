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

    public init(
        id: String,
        title: String,
        location: String,
        recordedAt: String,
        visibility: String,
        demo: Bool,
        videoURL: URL?,
        duration: Double,
        events: [JumpEvent]
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.recordedAt = recordedAt
        self.visibility = visibility
        self.demo = demo
        self.videoURL = videoURL
        self.duration = duration
        self.events = events
    }

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
    public let gForce: Double?
    public let acceleration: MotionVector?
    public let gravity: MotionVector?

    public init(
        time: Double,
        altitude: Double,
        verticalSpeed: Double,
        speed3D: Double,
        gForce: Double? = nil,
        acceleration: MotionVector? = nil,
        gravity: MotionVector? = nil
    ) {
        self.time = time
        self.altitude = altitude
        self.verticalSpeed = verticalSpeed
        self.speed3D = speed3D
        self.gForce = gForce
        self.acceleration = acceleration
        self.gravity = gravity
    }
}

public struct MotionVector: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var magnitude: Double { sqrt(x * x + y * y + z * z) }
}

public struct Telemetry: Codable, Sendable {
    public let jumpID: String
    /// videoTime = sampleTime + timeOffset
    public let timeOffset: Double
    public let altitudeReference: String
    public let samples: [TelemetrySample]

    public init(
        jumpID: String,
        timeOffset: Double,
        altitudeReference: String,
        samples: [TelemetrySample]
    ) {
        self.jumpID = jumpID
        self.timeOffset = timeOffset
        self.altitudeReference = altitudeReference
        self.samples = samples
    }
}

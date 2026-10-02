import SwiftUI
import AVKit
import Charts
import FreefallCore

@MainActor
final class ReplayModel: ObservableObject {
    @Published var time = 0.0
    @Published var telemetry: Telemetry?
    @Published var error: String?
    let player: AVPlayer
    private var observer: Any?
    private var engine = TelemetryEngine(samples: [])

    init(videoURL: URL?) {
        player = videoURL.map { AVPlayer(url: $0) } ?? AVPlayer()
    }

    var current: TelemetrySample? { engine.at(videoTime: time) }

    func load(jumpID: String) async {
        do {
            let data = try await AppConfiguration.api.telemetry(jumpID: jumpID)
            telemetry = data
            engine = TelemetryEngine(samples: data.samples, timeOffset: data.timeOffset)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func use(_ data: Telemetry?) {
        telemetry = data
        engine = TelemetryEngine(
            samples: data?.samples ?? [],
            timeOffset: data?.timeOffset ?? 0
        )
        error = nil
    }

    func observe() {
        guard observer == nil else { return }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] value in
            Task { @MainActor in
                if value.seconds.isFinite { self?.time = value.seconds }
            }
        }
    }

    func stop() {
        player.pause()
        if let observer { player.removeTimeObserver(observer); self.observer = nil }
    }

    func seek(to time: Double, hasVideo: Bool) {
        self.time = time
        if hasVideo { player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
    }
}

struct JumpDetailView: View {
    let jump: Jump
    let loadsRemoteTelemetry: Bool
    @StateObject private var replay: ReplayModel

    init(jump: Jump, loadsRemoteTelemetry: Bool = true) {
        self.jump = jump
        self.loadsRemoteTelemetry = loadsRemoteTelemetry
        _replay = StateObject(wrappedValue: ReplayModel(videoURL: jump.videoURL))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if jump.videoURL != nil {
                    VideoPlayer(player: replay.player).frame(height: 240)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "airplane").font(.system(size: 48)).foregroundStyle(.orange)
                        Text("Demo jump").font(.title.bold())
                        Text("Synthetic telemetry · no footage attached")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).frame(height: 220)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
                HStack(alignment: .top, spacing: 12) {
                    metric("\(estimatePrefix)Altitude · ft", replay.current.map { String(Int($0.altitude * 3.28084)) } ?? "—")
                    metric("\(estimatePrefix)Speed · km/h", replay.current.map { String(Int($0.speed3D * 3.6)) } ?? "—")
                    metric("Measured G-force", replay.current?.gForce.map { String(format: "%.2f g", $0) } ?? "—")
                }
                Text("\(phase) · \(Int(replay.time))s").font(.headline).foregroundStyle(.orange)
                if let sample = replay.current,
                   sample.acceleration != nil,
                   sample.gravity != nil {
                    FlightMotionPanel(sample: sample)
                }
                Slider(value: Binding(get: { replay.time }, set: { replay.seek(to: $0, hasVideo: jump.videoURL != nil) }), in: 0...max(jump.duration, 1))
                HStack {
                    ForEach(jump.events, id: \.kind) { event in
                        Button(event.kind.capitalized) {
                            replay.seek(to: event.time, hasVideo: jump.videoURL != nil)
                        }.buttonStyle(.bordered)
                    }
                }
                if let telemetry = replay.telemetry {
                    Text(telemetry.altitudeReference.hasPrefix("estimated_from_motion_model")
                         ? "Estimated altitude · not GPS"
                         : "Altitude above drop zone")
                        .font(.headline)
                    Chart {
                        ForEach(Array(telemetry.samples.enumerated()), id: \.offset) { _, sample in
                            LineMark(x: .value("Time · s", sample.time + telemetry.timeOffset), y: .value("Altitude · m", sample.altitude))
                                .foregroundStyle(.orange)
                        }
                        RuleMark(x: .value("Replay", replay.time)).foregroundStyle(.white.opacity(0.7))
                    }.frame(height: 180)
                    Text(telemetry.altitudeReference.hasPrefix("estimated_from_motion_model")
                         ? "G-force is measured. Speed and altitude use a generic freefall model anchored at the start of the video and will drift from reality."
                         : "Telemetry stays in metres and metres per second; this display uses feet and km/h.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = replay.error {
                    Text(error).foregroundStyle(.red)
                    Button("Retry telemetry") { Task { await replay.load(jumpID: jump.id) } }
                }
            }.padding(24)
        }
        .navigationTitle(jump.title).navigationBarTitleDisplayMode(.inline)
        .task {
            if jump.videoURL != nil { replay.observe() }
            if loadsRemoteTelemetry {
                await replay.load(jumpID: jump.id)
            } else {
                do { replay.use(try LocalJumpLibrary.shared.telemetry(jumpID: jump.id)) }
                catch { replay.error = error.localizedDescription }
            }
        }
        .onDisappear { replay.stop() }
    }

    private var phase: String {
        if !loadsRemoteTelemetry && jump.events.isEmpty { return "Motion estimate" }
        return jump.events.sorted { $0.time < $1.time }
            .last(where: { $0.time <= replay.time })?.kind.capitalized ?? "Aircraft"
    }
    private var estimatePrefix: String {
        replay.telemetry?.altitudeReference.hasPrefix("estimated_from_motion_model") == true ? "Est. " : ""
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlightMotionPanel: View {
    let sample: TelemetrySample

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Motion instruments", systemImage: "gyroscope")
                    .font(.headline)
                Spacer()
                Text("HELMET FRAME")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 8) {
                ArrowheadAttitude(
                    gravity: sample.gravity!,
                    acceleration: sample.acceleration!
                )
                Text("ATTITUDE + CAMERA G VECTOR")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(height: 240)
            Text("Assumes a right-way-up helmet mount. The arrowhead shows head attitude; the vector points toward helmet-relative acceleration, while the outer ring shows total G.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ArrowheadAttitude: View {
    let gravity: MotionVector
    let acceleration: MotionVector

    private var roll: Double { atan2(gravity.x, gravity.y) }
    private var pitch: Double {
        atan2(gravity.z, max(0.0001, hypot(gravity.x, gravity.y)))
    }
    private var totalG: Double { acceleration.magnitude / 9.80665 }
    private enum BodySide: String {
        case belly = "BELLY"
        case back = "BACK"
        case headDown = "HEAD DOWN"
        case headUp = "HEAD UP"
        case leftSide = "LEFT SIDE"
        case rightSide = "RIGHT SIDE"
    }
    private var normalizedGravity: MotionVector {
        let magnitude = max(0.0001, gravity.magnitude)
        return MotionVector(
            x: gravity.x / magnitude,
            y: gravity.y / magnitude,
            z: gravity.z / magnitude
        )
    }
    private var bodySide: BodySide {
        let vector = normalizedGravity
        let x = abs(vector.x)
        let y = abs(vector.y)
        let z = abs(vector.z)
        if y >= x && y >= z {
            return vector.y < 0 ? .back : .belly
        }
        if z >= x {
            return vector.z > 0 ? .headDown : .headUp
        }
        return vector.x > 0 ? .rightSide : .leftSide
    }
    private var arrowColor: Color {
        switch bodySide {
        case .belly: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .back: return Color(red: 0.96, green: 0.71, blue: 0.0)
        case .headDown: return Color(red: 0.95, green: 0.28, blue: 0.25)
        case .headUp: return Color(red: 0.2, green: 0.78, blue: 0.9)
        case .leftSide, .rightSide: return Color(red: 0.55, green: 0.57, blue: 0.61)
        }
    }
    private var faceScale: Double {
        max(0.2, min(1, abs(normalizedGravity.y) / 0.8))
    }
    private var forceColor: Color {
        switch totalG {
        case ..<0.5: return .cyan
        case ..<1.5: return .green
        case ..<3: return .orange
        default: return .red
        }
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.clip(to: Path(ellipseIn: rect))
            context.fill(Path(rect), with: .color(Color(red: 0.07, green: 0.25, blue: 0.43)))

            // Fixed cloud reference in the sky half.
            let cloudColor = GraphicsContext.Shading.color(Color(red: 0.82, green: 0.91, blue: 0.95).opacity(0.8))
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.63, y: size.height * 0.18, width: 42, height: 17)), with: cloudColor)
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.69, y: size.height * 0.12, width: 27, height: 25)), with: cloudColor)
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.76, y: size.height * 0.17, width: 30, height: 18)), with: cloudColor)

            let horizonY = center.y
            let earth = CGRect(x: 0, y: horizonY, width: size.width, height: size.height / 2)
            context.fill(Path(earth), with: .color(Color(red: 0.12, green: 0.2, blue: 0.19)))

            // Layered mountains stay fixed, making body rotation immediately legible.
            var distantMountain = Path()
            distantMountain.move(to: CGPoint(x: 0, y: size.height))
            distantMountain.addLine(to: CGPoint(x: 0, y: horizonY + 24))
            distantMountain.addLine(to: CGPoint(x: size.width * 0.28, y: horizonY - 7))
            distantMountain.addLine(to: CGPoint(x: size.width * 0.48, y: horizonY + 20))
            distantMountain.addLine(to: CGPoint(x: size.width * 0.7, y: horizonY - 15))
            distantMountain.addLine(to: CGPoint(x: size.width, y: horizonY + 24))
            distantMountain.addLine(to: CGPoint(x: size.width, y: size.height))
            distantMountain.closeSubpath()
            context.fill(distantMountain, with: .color(Color(red: 0.25, green: 0.34, blue: 0.4)))

            var nearMountain = Path()
            nearMountain.move(to: CGPoint(x: 0, y: size.height))
            nearMountain.addLine(to: CGPoint(x: 0, y: horizonY + 42))
            nearMountain.addLine(to: CGPoint(x: size.width * 0.38, y: horizonY + 5))
            nearMountain.addLine(to: CGPoint(x: size.width * 0.63, y: horizonY + 42))
            nearMountain.addLine(to: CGPoint(x: size.width, y: horizonY + 12))
            nearMountain.addLine(to: CGPoint(x: size.width, y: size.height))
            nearMountain.closeSubpath()
            context.fill(nearMountain, with: .color(Color(red: 0.12, green: 0.3, blue: 0.27)))

            var river = Path()
            river.move(to: CGPoint(x: size.width * 0.7, y: horizonY + 2))
            river.addCurve(
                to: CGPoint(x: size.width * 0.5, y: horizonY + size.height * 0.18),
                control1: CGPoint(x: size.width * 0.8, y: horizonY + size.height * 0.06),
                control2: CGPoint(x: size.width * 0.43, y: horizonY + size.height * 0.1)
            )
            river.addCurve(
                to: CGPoint(x: size.width * 0.66, y: size.height),
                control1: CGPoint(x: size.width * 0.62, y: horizonY + size.height * 0.27),
                control2: CGPoint(x: size.width * 0.76, y: size.height * 0.88)
            )
            context.stroke(
                river,
                with: .color(Color(red: 0.15, green: 0.73, blue: 0.78)),
                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                river,
                with: .color(.white.opacity(0.35)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            var fixedHorizon = Path()
            fixedHorizon.move(to: CGPoint(x: 0, y: horizonY))
            fixedHorizon.addLine(to: CGPoint(x: size.width, y: horizonY))
            context.stroke(fixedHorizon, with: .color(.white.opacity(0.7)), lineWidth: 1.5)

            let ringWidth = min(10, 3 + totalG * 2)
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: 5, dy: 5)),
                with: .color(forceColor),
                lineWidth: ringWidth
            )

            context.translateBy(x: center.x, y: center.y)
            let pitchOffset = CGFloat(pitch / (.pi / 2)) * size.height * 0.16
            context.translateBy(x: 0, y: pitchOffset)
            context.rotate(by: .radians(-roll))
            context.scaleBy(x: 1, y: max(0.35, abs(cos(pitch))))

            let scale = min(size.width, size.height) / 150
            context.scaleBy(x: scale, y: scale)

            // Acceleration is camera-relative, so it shares the arrowhead's
            // attitude transform. Three G reaches the edge of the scope.
            let gx = max(-3, min(3, acceleration.x / 9.80665))
            let gy = max(-3, min(3, acceleration.y / 9.80665))
            let forcePoint = CGPoint(x: gx / 3 * 62, y: -gy / 3 * 62)
            var forceVector = Path()
            forceVector.move(to: .zero)
            forceVector.addLine(to: forcePoint)
            context.stroke(
                forceVector,
                with: .color(forceColor),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: forcePoint.x - 6,
                    y: forcePoint.y - 6,
                    width: 12,
                    height: 12
                )),
                with: .color(forceColor)
            )

            var arrowhead = Path()
            context.scaleBy(x: faceScale, y: 1)
            arrowhead.move(to: CGPoint(x: 0, y: -48))
            arrowhead.addLine(to: CGPoint(x: 35, y: 36))
            arrowhead.addLine(to: CGPoint(x: 0, y: 20))
            arrowhead.addLine(to: CGPoint(x: -35, y: 36))
            arrowhead.closeSubpath()
            context.fill(arrowhead, with: .color(arrowColor))
            context.stroke(arrowhead, with: .color(.white.opacity(0.9)), lineWidth: 3)

            // Dorsal details are visible only when the back faces the camera.
            if bodySide == .back {
                context.fill(
                    Path(roundedRect: CGRect(x: -13, y: -18, width: 26, height: 24), cornerRadius: 5),
                    with: .color(Color.black.opacity(0.85))
                )
                context.stroke(
                    Path(roundedRect: CGRect(x: -13, y: -18, width: 26, height: 24), cornerRadius: 5),
                    with: .color(Color.black),
                    lineWidth: 2
                )

                var legStraps = Path()
                legStraps.move(to: CGPoint(x: -9, y: -1))
                legStraps.addCurve(
                    to: CGPoint(x: -20, y: 13),
                    control1: CGPoint(x: -16, y: 2),
                    control2: CGPoint(x: -20, y: 7)
                )
                legStraps.move(to: CGPoint(x: 9, y: -1))
                legStraps.addCurve(
                    to: CGPoint(x: 20, y: 13),
                    control1: CGPoint(x: 16, y: 2),
                    control2: CGPoint(x: 20, y: 7)
                )
                context.stroke(
                    legStraps,
                    with: .color(Color.black.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
            }

            var centerline = Path()
            centerline.move(to: CGPoint(x: 0, y: -35))
            centerline.addLine(to: CGPoint(x: 0, y: 18))
            let centerStyle = bodySide == .back
                ? StrokeStyle(lineWidth: 2, dash: [6, 4])
                : StrokeStyle(lineWidth: 2)
            context.stroke(centerline, with: .color(.white.opacity(0.75)), style: centerStyle)
        }
        .overlay {
            ZStack {
                Circle().stroke(.white.opacity(0.8), lineWidth: 2)
                Circle().stroke(.white.opacity(0.12), lineWidth: 1).padding(18)
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%.2f g", totalG))
                    .font(.headline.monospacedDigit().bold())
                    .foregroundStyle(forceColor)
                Text("HELMET G")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(bodySide.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(arrowColor)
                Text("EST. HELMET ORIENTATION")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(14)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

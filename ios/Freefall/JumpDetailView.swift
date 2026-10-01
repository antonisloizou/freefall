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
    @StateObject private var replay: ReplayModel

    init(jump: Jump) {
        self.jump = jump
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
                HStack {
                    metric("Altitude · ft", replay.current.map { String(Int($0.altitude * 3.28084)) } ?? "—")
                    Spacer()
                    metric("3D speed · km/h", replay.current.map { String(Int($0.speed3D * 3.6)) } ?? "—")
                }
                Text("\(phase) · \(Int(replay.time))s").font(.headline).foregroundStyle(.orange)
                Slider(value: Binding(get: { replay.time }, set: { replay.seek(to: $0, hasVideo: jump.videoURL != nil) }), in: 0...max(jump.duration, 1))
                HStack {
                    ForEach(jump.events, id: \.kind) { event in
                        Button(event.kind.capitalized) {
                            replay.seek(to: event.time, hasVideo: jump.videoURL != nil)
                        }.buttonStyle(.bordered)
                    }
                }
                if let telemetry = replay.telemetry {
                    Text("Altitude above drop zone").font(.headline)
                    Chart {
                        ForEach(Array(telemetry.samples.enumerated()), id: \.offset) { _, sample in
                            LineMark(x: .value("Time · s", sample.time + telemetry.timeOffset), y: .value("Altitude · m", sample.altitude))
                                .foregroundStyle(.orange)
                        }
                        RuleMark(x: .value("Replay", replay.time)).foregroundStyle(.white.opacity(0.7))
                    }.frame(height: 180)
                    Text("Telemetry stays in metres and metres per second; this display uses feet and km/h.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = replay.error {
                    Text(error).foregroundStyle(.red)
                    Button("Retry telemetry") { Task { await replay.load(jumpID: jump.id) } }
                }
            }.padding(24)
        }
        .navigationTitle(jump.title).navigationBarTitleDisplayMode(.inline)
        .task { if jump.videoURL != nil { replay.observe() }; await replay.load(jumpID: jump.id) }
        .onDisappear { replay.stop() }
    }

    private var phase: String {
        jump.events.sorted { $0.time < $1.time }.last(where: { $0.time <= replay.time })?.kind.capitalized ?? "Aircraft"
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.largeTitle.monospacedDigit().bold())
        }
    }
}

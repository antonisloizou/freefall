import SwiftUI
import FreefallCore

struct JumpListView: View {
    @State private var jumps: [Jump] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Relive your jump.")
                        .font(.largeTitle.bold())
                    Text("Your footage. Your flight. Every moment.")
                        .foregroundStyle(.secondary)
                    if loading && jumps.isEmpty { ProgressView("Loading jumps…") }
                    if let error {
                        ContentUnavailableView {
                            Label("Cannot load jumps", systemImage: "wifi.exclamationmark")
                        } description: { Text(error) } actions: {
                            Button("Retry") { Task { await load() } }
                        }
                    } else if !loading && jumps.isEmpty {
                        ContentUnavailableView("No jumps yet", systemImage: "airplane")
                    }
                    ForEach(jumps) { jump in
                        NavigationLink {
                            JumpDetailView(jump: jump)
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "airplane")
                                    Spacer()
                                    if jump.demo { Text("DEMO").font(.caption.bold()) }
                                }
                                Text(jump.title).font(.title2.bold())
                                Text(jump.location).foregroundStyle(.secondary)
                                if let duration = jump.freefallDuration {
                                    Text("\(Int(duration)) seconds of freefall")
                                        .font(.headline).foregroundStyle(.orange)
                                }
                            }
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                    }
                }.padding(24)
            }
            .navigationTitle("FREEFALL")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
        }.preferredColorScheme(.dark).tint(.orange)
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        do { jumps = try await AppConfiguration.api.jumps(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

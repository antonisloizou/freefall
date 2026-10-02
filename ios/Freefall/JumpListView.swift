import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FreefallCore

struct JumpListView: View {
    @State private var remoteJumps: [Jump] = []
    @State private var localJumps: [Jump] = []
    @State private var error: String?
    @State private var importError: String?
    @State private var loading = false
    @State private var importing = false
    @State private var showingImporter = false
    @State private var showingPhotosPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    private var jumps: [Jump] { localJumps + remoteJumps }
    private var localJumpIDs: Set<String> { Set(localJumps.map(\.id)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Relive your jump.")
                        .font(.largeTitle.bold())
                    Text("Your footage. Your flight. Every moment.")
                        .foregroundStyle(.secondary)
                    if loading && jumps.isEmpty { ProgressView("Loading jumps…") }
                    if let importError {
                        Label(importError, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    if let error, jumps.isEmpty {
                        ContentUnavailableView {
                            Label("Cannot load jumps", systemImage: "wifi.exclamationmark")
                        } description: { Text(error) } actions: {
                            Button("Retry") { Task { await load() } }
                        }
                    } else if let error {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if !loading && jumps.isEmpty {
                        ContentUnavailableView("No jumps yet", systemImage: "airplane")
                    }
                    ForEach(jumps) { jump in
                        NavigationLink {
                            JumpDetailView(
                                jump: jump,
                                loadsRemoteTelemetry: !localJumpIDs.contains(jump.id)
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "airplane")
                                    Spacer()
                                    if localJumpIDs.contains(jump.id) {
                                        Label("PRIVATE", systemImage: "lock.fill")
                                            .font(.caption.bold())
                                    } else if jump.demo {
                                        Text("DEMO").font(.caption.bold())
                                    }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingPhotosPicker = true
                        } label: {
                            Label("Import from Photos", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Browse Files", systemImage: "folder")
                        }
                    } label: {
                        if importing {
                            ProgressView()
                        } else {
                            Label("Import Video", systemImage: "plus")
                        }
                    }
                    .disabled(importing)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .photosPicker(
                isPresented: $showingPhotosPicker,
                selection: $selectedPhoto,
                matching: .videos
            )
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.movie]
            ) { result in
                switch result {
                case .success(let url):
                    Task { await importVideo(from: url) }
                case .failure(let error):
                    if !error.isCancellation { importError = error.localizedDescription }
                }
            }
        }.preferredColorScheme(.dark).tint(.orange)
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        do { localJumps = try LocalJumpLibrary.shared.load() }
        catch { importError = "Local jumps could not be loaded: \(error.localizedDescription)" }
        do { remoteJumps = try await AppConfiguration.api.jumps(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    @MainActor private func importVideo(from url: URL) async {
        importing = true
        importError = nil
        defer { importing = false }
        do {
            let jump = try await LocalJumpLibrary.shared.importVideo(from: url)
            localJumps.insert(jump, at: 0)
        } catch {
            importError = "Video could not be imported: \(error.localizedDescription)"
        }
    }

    @MainActor private func importPhoto(_ item: PhotosPickerItem) async {
        importing = true
        importError = nil
        defer {
            importing = false
            selectedPhoto = nil
        }
        do {
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                throw CocoaError(.fileReadUnknown)
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            let jump = try await LocalJumpLibrary.shared.importVideo(from: movie.url)
            localJumps.insert(jump, at: 0)
        } catch {
            importError = "Video could not be imported: \(error.localizedDescription)"
        }
    }
}

private extension Error {
    var isCancellation: Bool {
        let error = self as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}

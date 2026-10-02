import AVFoundation
import CoreTransferable
import Foundation
import FreefallCore
import UniformTypeIdentifiers

struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileExtension = received.file.pathExtension.isEmpty
                ? "mp4"
                : received.file.pathExtension
            let temporaryURL = FileManager.default.temporaryDirectory
                .appending(path: "photo-\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: received.file, to: temporaryURL)
            return ImportedMovie(url: temporaryURL)
        }
    }
}

private struct LocalJumpRecord: Codable {
    let id: String
    let title: String
    let recordedAt: String
    let videoFilename: String
    let duration: Double
    let telemetryFilename: String?
}

@MainActor
final class LocalJumpLibrary {
    static let shared = LocalJumpLibrary()

    private let fileManager: FileManager
    private let directoryURL: URL
    private let indexURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        directoryURL = applicationSupport
            .appending(path: "Freefall", directoryHint: .isDirectory)
        indexURL = directoryURL.appending(path: "local-jumps.json")
    }

    func load() throws -> [Jump] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let records = try JSONDecoder().decode([LocalJumpRecord].self, from: data)
        return records.compactMap(makeJump)
    }

    func importVideo(from sourceURL: URL) async throws -> Jump {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let id = "local-\(UUID().uuidString.lowercased())"
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let fileExtension = sourceExtension.isEmpty ? "mp4" : sourceExtension
        let filename = "\(id).\(fileExtension)"
        let destinationURL = directoryURL.appending(path: filename)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        var telemetryURL: URL?
        do {
            let duration = try await videoDuration(at: destinationURL)
            let title = sourceURL.deletingPathExtension().lastPathComponent
            let telemetry = try GPMFMotionExtractor().telemetry(
                videoURL: destinationURL,
                jumpID: id
            )
            if let telemetry {
                let url = directoryURL.appending(path: "\(id)-telemetry.json")
                try JSONEncoder().encode(telemetry).write(to: url, options: .atomic)
                telemetryURL = url
            }
            let record = LocalJumpRecord(
                id: id,
                title: title.isEmpty ? "Imported jump" : title,
                recordedAt: ISO8601DateFormatter().string(from: Date()),
                videoFilename: filename,
                duration: duration,
                telemetryFilename: telemetryURL?.lastPathComponent
            )
            var records = try loadRecords()
            records.insert(record, at: 0)
            try save(records)
            return makeJump(record)!
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if let telemetryURL { try? fileManager.removeItem(at: telemetryURL) }
            throw error
        }
    }

    func telemetry(jumpID: String) throws -> Telemetry? {
        guard let record = try loadRecords().first(where: { $0.id == jumpID }),
              let filename = record.telemetryFilename else { return nil }
        let url = directoryURL.appending(path: filename)
        let telemetry = try JSONDecoder().decode(
            Telemetry.self,
            from: Data(contentsOf: url)
        )
        if telemetry.altitudeReference != "estimated_from_motion_model_helmet_zxy_v1" {
            let videoURL = directoryURL.appending(path: record.videoFilename)
            if let upgraded = try GPMFMotionExtractor().telemetry(
                videoURL: videoURL,
                jumpID: jumpID
            ) {
                try JSONEncoder().encode(upgraded).write(to: url, options: .atomic)
                return upgraded
            }
        }
        return telemetry
    }

    private func loadRecords() throws -> [LocalJumpRecord] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode(
            [LocalJumpRecord].self,
            from: Data(contentsOf: indexURL)
        )
    }

    private func save(_ records: [LocalJumpRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: indexURL, options: .atomic)
    }

    private func makeJump(_ record: LocalJumpRecord) -> Jump? {
        let videoURL = directoryURL.appending(path: record.videoFilename)
        guard fileManager.fileExists(atPath: videoURL.path) else { return nil }
        return Jump(
            id: record.id,
            title: record.title,
            location: "Local import",
            recordedAt: record.recordedAt,
            visibility: "private",
            demo: false,
            videoURL: videoURL,
            duration: record.duration,
            events: []
        )
    }

    private func videoDuration(at url: URL) async throws -> Double {
        let duration = try await AVURLAsset(url: url).load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return seconds
    }
}

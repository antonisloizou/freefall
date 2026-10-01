import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct APIClient: Sendable {
    public let baseURL: URL
    public init(baseURL: URL) { self.baseURL = baseURL }

    public func jumps() async throws -> [Jump] { try await get("v1/jumps") }
    public func telemetry(jumpID: String) async throws -> Telemetry {
        try await get("v1/jumps/\(jumpID)/telemetry")
    }

    private func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: path))
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

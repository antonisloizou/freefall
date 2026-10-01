import SwiftUI
import FreefallCore

@main
struct FreefallApp: App {
    var body: some Scene {
        WindowGroup { JumpListView() }
    }
}

enum AppConfiguration {
    static var api: APIClient {
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? ""
        // The simulator can reach the Mac using localhost. A physical phone needs
        // the Mac's LAN address or a hosted HTTPS endpoint in Config.xcconfig.
        let url = URL(string: raw).flatMap { $0.host == nil ? nil : $0 } ?? URL(string: "http://localhost:8080")!
        return APIClient(baseURL: url)
    }
}

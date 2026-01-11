import SwiftUI
import AppKit

@MainActor
final class OpenWorkspacesStore: ObservableObject {

    // MARK: - Singleton
    static let shared = OpenWorkspacesStore()

    // MARK: - Published Properties
    @Published private(set) var urls: [URL] = []

    // MARK: - Properties
    private let key = "podosoju_openWorkspaceURLs"
    var isTerminating = false
    var didBootstrapRestore = false   // 이번 런치에서 복원 시도했는지

    // MARK: - Initialization
    private init() {
        load()
    }

    // MARK: - Methods
    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([URL].self, from: data)
        else {
            urls = []
            return
        }
        urls = decoded
    }

    func persist() {
        let data = (try? JSONEncoder().encode(urls)) ?? Data()
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ url: URL) {
        if !urls.contains(url) {
            urls.append(url)
            persist()
        }
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        persist()
    }
}

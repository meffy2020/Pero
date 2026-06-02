import SwiftUI
import Foundation
import PeroCore

@main
struct PeroApp: App {
    private let provider: PeroAPIProviding
    private let locationProvider: LocationProviding

    init() {
        provider = AppRuntimeConfiguration.makeProvider()
        locationProvider = CoreLocationProvider()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(provider: provider, locationProvider: locationProvider)
        }
    }
}

enum AppRuntimeConfiguration {
    static func makeProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> PeroAPIProviding {
        if environment["PERO_USE_PREVIEW"] == "1" {
            return PeroAPIProviderFactory.preview()
        }

        let baseURLString = environment["PERO_API_BASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "PERO_API_BASE_URL") as? String
            ?? "http://127.0.0.1:8080"

        guard let baseURL = resolvedLiveBaseURL(baseURLString) else {
            preconditionFailure("Invalid PERO_API_BASE_URL: \(baseURLString)")
        }
        return PeroAPIProviderFactory.live(baseURL: baseURL)
    }

    static func resolvedLiveBaseURL(_ baseURLString: String) -> URL? {
        guard
            let baseURL = URL(string: baseURLString),
            let scheme = baseURL.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            baseURL.host != nil
        else {
            return nil
        }
        return baseURL
    }
}

import SwiftUI
import Foundation
import PeroCore

@main
struct PeroApp: App {
    private let provider: PeroAPIProviding
    private let locationProvider: LocationProviding

    init() {
        provider = AppRuntimeConfiguration.makeProvider()
        locationProvider = AppRuntimeConfiguration.makeLocationProvider()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(provider: provider, locationProvider: locationProvider)
        }
    }
}

enum AppRuntimeConfiguration {
    static func usesPreviewData(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["PERO_USE_PREVIEW"] == "1"
    }

    static func makeProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> PeroAPIProviding {
        if usesPreviewData(environment: environment) {
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

    static func makeLocationProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LocationProviding {
        if usesPreviewData(environment: environment) {
            return StaticLocationProvider.preview
        }

        return CoreLocationProvider()
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

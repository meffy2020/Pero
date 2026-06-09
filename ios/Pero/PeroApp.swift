import SwiftUI
import Foundation
import PeroCore
import KakaoMapsSDK
import KakaoSDKCommon

@main
struct PeroApp: App {
    private let provider: PeroAPIProviding
    private let locationProvider: LocationProviding

    init() {
        AppRuntimeConfiguration.initializeKakaoMaps()
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
    static func initializeKakaoMaps(bundle: Bundle = .main) {
        guard
            let appKey = bundle.object(forInfoDictionaryKey: "KAKAO_MAP_APP_KEY") as? String,
            !appKey.isEmpty
        else {
            preconditionFailure("Missing KAKAO_MAP_APP_KEY")
        }
        SDKInitializer.InitSDK(appKey: appKey, phase: .real)
        KakaoSDK.initSDK(appKey: appKey)
        #if DEBUG
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let keySuffix = String(appKey.suffix(6))
        print("Kakao Maps init: bundleID=\(bundleID), keySuffix=\(keySuffix), phase=real")
        #endif
    }

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
        #if DEBUG
        print("Pero API baseURL=\(baseURL.absoluteString)")
        #endif
        return PeroAPIProviderFactory.live(baseURL: baseURL)
    }

    static func makeLocationProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LocationProviding {
        if usesPreviewData(environment: environment) {
            return StaticLocationProvider.preview
        }

        #if targetEnvironment(simulator)
        return StaticLocationProvider.preview
        #else
        return CoreLocationProvider()
        #endif
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

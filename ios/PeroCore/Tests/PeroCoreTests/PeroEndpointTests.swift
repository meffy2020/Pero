import Foundation
import Testing
@testable import PeroCore

@Test func eventsEndpointBuildsExpectedQueryAndPreservesBasePath() throws {
    let request = try PeroEndpoint.events(region: "서울", themeId: "pet", activeOn: "2026-06-02", limit: 5)
        .urlRequest(baseURL: try #require(URL(string: "https://example.com/pero")))

    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/pero/api/events")
    let components = try #require(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []
    #expect(items.contains(URLQueryItem(name: "region", value: "서울")))
    #expect(items.contains(URLQueryItem(name: "themeId", value: "pet")))
    #expect(items.contains(URLQueryItem(name: "activeOn", value: "2026-06-02")))
    #expect(items.contains(URLQueryItem(name: "limit", value: "5")))
}

@Test func postEndpointsSetMethodAndAcceptHeader() throws {
    let request = try PeroEndpoint.search.urlRequest(baseURL: try #require(URL(string: "https://api.example.test")))

    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/search")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
}

import Foundation
import Testing
@testable import PeroCore

@Test func eventsEndpointBuildsExpectedQueryAndPreservesBasePath() throws {
    let request = try PeroEndpoint.events(region: "서울", themeId: "pet", activeOn: "2026-06-02", limit: 5)
        .urlRequest(baseURL: try #require(URL(string: "https://example.com/pero")))

    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/pero/api/events")
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []
    #expect(items.contains(URLQueryItem(name: "region", value: "서울")))
    #expect(items.contains(URLQueryItem(name: "themeId", value: "pet")))
    #expect(items.contains(URLQueryItem(name: "activeOn", value: "2026-06-02")))
    #expect(items.contains(URLQueryItem(name: "limit", value: "5")))
}

@Test func placesEndpointBuildsLightweightPoolQuery() throws {
    let request = try PeroEndpoint.places(
        PlacesQuery(
            latitude: 37.5665,
            longitude: 126.978,
            radiusKm: 3,
            north: 37.7,
            south: 37.4,
            east: 127.1,
            west: 126.8,
            zoom: 12,
            density: "detail",
            category: "관광지",
            mode: "tour",
            source: "koreaTour",
            activeFestival: true,
            limit: 360,
            includeTourApi: false
        )
    )
    .urlRequest(baseURL: try #require(URL(string: "https://example.com/pero")))

    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/pero/api/places")
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []
    #expect(items.contains(URLQueryItem(name: "latitude", value: "37.5665")))
    #expect(items.contains(URLQueryItem(name: "longitude", value: "126.978")))
    #expect(items.contains(URLQueryItem(name: "radiusKm", value: "3.0")))
    #expect(items.contains(URLQueryItem(name: "north", value: "37.7")))
    #expect(items.contains(URLQueryItem(name: "south", value: "37.4")))
    #expect(items.contains(URLQueryItem(name: "east", value: "127.1")))
    #expect(items.contains(URLQueryItem(name: "west", value: "126.8")))
    #expect(items.contains(URLQueryItem(name: "zoom", value: "12.0")))
    #expect(items.contains(URLQueryItem(name: "density", value: "detail")))
    #expect(items.contains(URLQueryItem(name: "category", value: "관광지")))
    #expect(items.contains(URLQueryItem(name: "mode", value: "tour")))
    #expect(items.contains(URLQueryItem(name: "source", value: "koreaTour")))
    #expect(items.contains(URLQueryItem(name: "activeFestival", value: "true")))
    #expect(items.contains(URLQueryItem(name: "limit", value: "360")))
    #expect(items.contains(URLQueryItem(name: "includeTourApi", value: "false")))
}

@Test func postEndpointsSetMethodAndAcceptHeader() throws {
    let request = try PeroEndpoint.search.urlRequest(baseURL: try #require(URL(string: "https://api.example.test")))

    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/search")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
}

@Test func themeEndpointPercentEncodesPathSegment() throws {
    let request = try PeroEndpoint.theme(id: "pet/course 서울")
        .urlRequest(baseURL: try #require(URL(string: "https://example.com/pero")))

    #expect(request.url?.path == "/pero/api/themes/pet%2Fcourse%20%EC%84%9C%EC%9A%B8")
}

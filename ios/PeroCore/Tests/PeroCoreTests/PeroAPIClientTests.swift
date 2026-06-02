import Foundation
import Testing
@testable import PeroCore

@Test func clientEncodesSearchRequestAndDecodesSearchResponse() async throws {
    let transport = MockHTTPTransport(responseBody: searchResponseJSON)
    let client = PeroAPIClient(baseURL: try #require(URL(string: "https://api.example.test")), transport: transport)

    let response = try await client.search(SearchRequest(query: "반려동물 산책", mode: .hybrid, topK: 3))

    let sentRequest = try await transport.onlyRequest()
    #expect(sentRequest.url?.path == "/api/search")
    #expect(sentRequest.httpMethod == "POST")
    #expect(sentRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try #require(sentRequest.httpBody)
    let bodyObject = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(bodyObject?["query"] as? String == "반려동물 산책")
    #expect(bodyObject?["mode"] as? String == "HYBRID")
    #expect(bodyObject?["topK"] as? Int == 3)

    #expect(response.query == "반려동물 산책")
    #expect(response.mode == .hybrid)
    #expect(response.source.providerId == "smartSeoul,koreaTour")
    #expect(response.results.first?.tourApi?.images.count == 0)
}

@Test func clientThrowsTypedStatusError() async throws {
    let transport = MockHTTPTransport(statusCode: 503, responseBody: Data("{}".utf8))
    let client = PeroAPIClient(baseURL: try #require(URL(string: "https://api.example.test")), transport: transport)

    do {
        let _: HealthResponse = try await client.health()
        Issue.record("Expected unacceptableStatus error")
    } catch let error as PeroAPIError {
        #expect(error == .unacceptableStatus(503))
    }
}

@Test func previewProviderSuppliesOfflineMVPData() async throws {
    let provider = PeroAPIProviderFactory.preview()

    let places = try await provider.places()
    let search = try await provider.search(SearchRequest(query: "서울"))

    #expect(places.total == 1)
    #expect(search.mode == .hybrid)
    #expect(search.results.first?.name == "서울 반려 산책 공원")
}

actor MockHTTPTransport: HTTPTransport {
    private let statusCode: Int
    private let responseBody: Data
    private var requests: [URLRequest] = []

    init(statusCode: Int = 200, responseBody: Data) {
        self.statusCode = statusCode
        self.responseBody = responseBody
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (responseBody, response)
    }

    func onlyRequest() async throws -> URLRequest {
        try #require(requests.count == 1)
        return try #require(requests.first)
    }
}

private let searchResponseJSON = Data(
    #"""
    {
      "query": "반려동물 산책",
      "themeId": null,
      "mode": "HYBRID",
      "total": 1,
      "topK": 3,
      "generatedAt": "2026-06-02T08:00:00.000Z",
      "source": {
        "providerId": "smartSeoul,koreaTour",
        "providerName": "스마트서울맵 캐시 + 한국관광공사 API 동기화 캐시",
        "status": "loaded",
        "generatedAt": "2026-06-02T08:00:00.000Z",
        "count": 100
      },
      "results": [
        {
          "id": "p-1",
          "name": "서울 반려 산책 공원",
          "category": "공원",
          "district": "중구",
          "address": "서울특별시 중구",
          "roadAddress": "서울특별시 중구 세종대로",
          "summary": "반려동물과 산책하기 좋은 장소",
          "tags": ["반려동물", "산책"],
          "themeTags": ["pet"],
          "latitude": 37.5665,
          "longitude": 126.978,
          "sourceAttribution": "Preview",
          "distanceKm": 1.2,
          "evidence": "검색 근거",
          "keywordScore": 0.9,
          "vectorScore": 0.2,
          "featureScore": 0.3,
          "geoScore": 0.4,
          "finalScore": 0.95,
          "tourApi": {
            "contentId": "1",
            "contentTypeId": "12",
            "contentTypeLabel": "관광지",
            "common": null,
            "intro": null,
            "images": null,
            "pet": null
          }
        }
      ]
    }
    """#.utf8
)

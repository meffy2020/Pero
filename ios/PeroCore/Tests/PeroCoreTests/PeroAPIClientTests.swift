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

@Test func clientEncodesRecommendationRequestAndDecodesResponse() async throws {
    let transport = MockHTTPTransport(responseBody: recommendationResponseJSON)
    let client = PeroAPIClient(baseURL: try #require(URL(string: "https://api.example.test/pero")), transport: transport)

    let response = try await client.recommendations(
        RecommendationRequest(
            themeId: "go-now",
            latitude: 35.1796,
            longitude: 129.0756,
            radiusKm: 3,
            north: 35.3,
            south: 35.1,
            east: 129.2,
            west: 128.9,
            zoom: 13,
            density: "detail",
            category: "관광지",
            mode: "tour",
            limit: 20,
            recentPlaceIds: ["p-old"],
            includeTourApi: false
        )
    )

    let sentRequest = try await transport.onlyRequest()
    #expect(sentRequest.url?.path == "/pero/api/recommendations")
    #expect(sentRequest.httpMethod == "POST")
    #expect(sentRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try #require(sentRequest.httpBody)
    let bodyObject = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(bodyObject?["themeId"] as? String == "go-now")
    #expect(bodyObject?["latitude"] as? Double == 35.1796)
    #expect(bodyObject?["longitude"] as? Double == 129.0756)
    #expect(bodyObject?["radiusKm"] as? Double == 3)
    #expect(bodyObject?["north"] as? Double == 35.3)
    #expect(bodyObject?["south"] as? Double == 35.1)
    #expect(bodyObject?["east"] as? Double == 129.2)
    #expect(bodyObject?["west"] as? Double == 128.9)
    #expect(bodyObject?["zoom"] as? Double == 13)
    #expect(bodyObject?["density"] as? String == "detail")
    #expect(bodyObject?["category"] as? String == "관광지")
    #expect(bodyObject?["mode"] as? String == "tour")
    #expect(bodyObject?["limit"] as? Int == 20)
    #expect(bodyObject?["recentPlaceIds"] as? [String] == ["p-old"])
    #expect(bodyObject?["includeTourApi"] as? Bool == false)

    #expect(response.source.providerId == "smartSeoul,koreaTour")
    #expect(response.fallbackUsed)
    #expect(response.randomScope == "현재 지도 안에서 랜덤")
    #expect(response.nearbyPick?.place?.themeTags == ["go-now"])
    #expect(response.mealPick?.place?.name == "도심 간편 식당가")
    #expect(response.dateCourse?.stops.count == 1)
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

    #expect(places.total == 3)
    #expect(search.mode == .hybrid)
    #expect(search.results.first?.name == "서울 반려 산책 공원")

    let recommendations = try await provider.recommendations(RecommendationRequest(themeId: "go-now"))
    #expect(recommendations.fallbackUsed)
    #expect(recommendations.nearbyPick?.place?.themeTags == ["go-now"])
    #expect(recommendations.mealPick?.place?.distanceKm == 1.1)
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


private let recommendationResponseJSON = Data(
    #"""
    {
      "generatedAt": "2026-06-02T08:00:00.000Z",
      "source": {
        "providerId": "smartSeoul,koreaTour",
        "providerName": "스마트서울맵 캐시 + 한국관광공사 API 동기화 캐시",
        "status": "loaded",
        "generatedAt": "2026-06-02T08:00:00.000Z",
        "count": 100
      },
      "fallbackUsed": true,
      "randomScope": "현재 지도 안에서 랜덤",
      "nearbyPick": {
        "key": "nearby",
        "title": "가까운 산책 추천",
        "description": "현재 위치에서 이동 부담이 낮고 바로 설명 가능한 장소입니다.",
        "place": {
          "id": "preview-seoul-park",
          "name": "서울 반려 산책 공원",
          "category": "공원",
          "district": "중구",
          "roadAddress": "서울특별시 중구 세종대로",
          "summary": "현재 위치 기준 산책 동선이 짧은 미리보기 장소입니다.",
          "tags": ["산책", "반려동물"],
          "themeTags": ["go-now"],
          "latitude": 37.5665,
          "longitude": 126.978,
          "sourceAttribution": "Preview",
          "distanceKm": 0.8,
          "reason": "현재 위치에서 가깝고 야외 동선이 단순합니다.",
          "tourApi": null
        }
      },
      "mealPick": {
        "key": "meal",
        "title": "가벼운 식사 후 이동",
        "description": "짧은 식사와 주변 산책을 묶어 지금 가기 좋습니다.",
        "place": {
          "id": "preview-market",
          "name": "도심 간편 식당가",
          "category": "음식점",
          "district": "중구",
          "roadAddress": "서울특별시 중구 무교로",
          "summary": "식사 후 이동하기 쉬운 미리보기 장소입니다.",
          "tags": ["식사", "도보"],
          "themeTags": ["go-now"],
          "latitude": 37.5677,
          "longitude": 126.9794,
          "sourceAttribution": "Preview",
          "distanceKm": 1.1,
          "reason": "짧은 식사와 다음 장소 이동을 함께 설명할 수 있습니다.",
          "tourApi": null
        }
      },
      "dateCourse": {
        "title": "지금 출발 코스",
        "description": "실내 전시와 산책을 함께 묶은 설명 우선 코스입니다.",
        "stops": [
          {
            "slot": "1차 확인",
            "place": {
              "id": "preview-gallery",
              "name": "시청 인근 전시 공간",
              "category": "전시",
              "district": "중구",
              "roadAddress": "서울특별시 중구 세종대로",
              "summary": "날씨 영향을 덜 받는 실내 미리보기 장소입니다.",
              "tags": ["실내", "전시"],
              "themeTags": ["go-now"],
              "latitude": 37.5651,
              "longitude": 126.9759,
              "sourceAttribution": "Preview",
              "distanceKm": 1.4,
              "reason": "비가 와도 설명 가능한 실내 동선을 제공합니다.",
              "tourApi": null
            }
          }
        ]
      }
    }
    """#.utf8
)

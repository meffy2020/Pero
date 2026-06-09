package com.pero.search.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.pero.search.dto.RecommendationResponse;
import com.pero.search.dto.PlacesResponse;
import com.pero.search.dto.SearchResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class SearchControllerIntegrationTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    private String themeId;

    @BeforeEach
    void setUpThemeId() throws Exception {
        String body = mockMvc.perform(get("/api/themes"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);
        themeId = json.get(0).path("themeId").asText();
    }

    @Test
    void healthEndpointReturnsServiceStatus() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.service").value("pero-backend"))
                .andExpect(jsonPath("$.status").value("ok"));
    }

    @Test
    void placesEndpointReturnsSeedData() throws Exception {
        String body = mockMvc.perform(get("/api/places"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").exists())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);
        PlacesResponse response = objectMapper.readValue(body, PlacesResponse.class);

        assertThat(response.total()).isEqualTo(response.places().size());
        assertThat(response.source()).isNotNull();
        assertThat(response.source().providerId()).isNotBlank();
        assertThat(response.source().providerName()).isNotBlank();
        assertThat(response.source().status()).isNotBlank();
        assertThat(response.source().count()).isGreaterThanOrEqualTo(response.places().size());
        assertThat(json.path("places").get(0).has("tourApi")).isTrue();
    }

    @Test
    void placesEndpointCanReturnLightweightNearbyPool() throws Exception {
        String body = mockMvc.perform(get("/api/places")
                        .param("latitude", "37.5665")
                        .param("longitude", "126.9780")
                        .param("limit", "12")
                        .param("includeTourApi", "false"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);
        PlacesResponse response = objectMapper.readValue(body, PlacesResponse.class);

        assertThat(response.total()).isLessThanOrEqualTo(12);
        assertThat(response.places()).hasSize(response.total());
        assertThat(response.source().count()).isGreaterThanOrEqualTo(response.total());
        assertThat(json.path("places").get(0).path("tourApi").isNull()).isTrue();
    }


    @Test
    void placesEndpointSupportsBoundsCategoryLowZoomAndMetadata() throws Exception {
        String seedBody = mockMvc.perform(get("/api/places")
                        .param("limit", "1")
                        .param("includeTourApi", "false"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        JsonNode seed = objectMapper.readTree(seedBody).path("places").get(0);
        String category = seed.path("category").asText();

        String body = mockMvc.perform(get("/api/places")
                        .param("north", "38.0")
                        .param("south", "33.0")
                        .param("east", "132.0")
                        .param("west", "124.0")
                        .param("category", category)
                        .param("zoom", "8")
                        .param("limit", "500")
                        .param("includeTourApi", "false"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.generatedAt").exists())
                .andExpect(jsonPath("$.fallbackUsed").isBoolean())
                .andExpect(jsonPath("$.randomScope").exists())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);
        PlacesResponse response = objectMapper.readValue(body, PlacesResponse.class);

        assertThat(response.total()).isLessThanOrEqualTo(80);
        assertThat(response.places()).isNotEmpty();
        assertThat(response.places()).allSatisfy(place -> assertThat(place.category()).isEqualTo(category));
        assertThat(json.path("places").get(0).path("tourApi").isNull()).isTrue();
        assertThat(json.path("randomScope").asText()).contains("낮은 줌");
    }



    @Test
    void placesEndpointUsesKakaoCacheForRestaurantCandidatesInBounds() throws Exception {
        String body = mockMvc.perform(get("/api/places")
                        .param("latitude", "37.6542")
                        .param("longitude", "127.0568")
                        .param("radiusKm", "3")
                        .param("north", "37.68")
                        .param("south", "37.61")
                        .param("east", "127.10")
                        .param("west", "127.02")
                        .param("mode", "restaurant")
                        .param("source", "kakaoLocal")
                        .param("limit", "20")
                        .param("includeTourApi", "false"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.fallbackUsed").value(false))
                .andExpect(jsonPath("$.cacheMiss").value(false))
                .andReturn()
                .getResponse()
                .getContentAsString();

        PlacesResponse response = objectMapper.readValue(body, PlacesResponse.class);

        assertThat(response.total()).isPositive();
        assertThat(response.randomScope()).contains("source=kakaoLocal");
        assertThat(response.places()).allSatisfy(place -> assertThat(place.sourceAttribution()).isEqualTo("kakaoLocal"));
        assertThat(response.places()).anySatisfy(place ->
                assertThat(place.address() + place.roadAddress() + place.name()).containsAnyOf("노원", "하계", "중계", "상계", "공릉"));
    }

    @Test
    void placesEndpointDoesNotExpandKakaoSourceOutsideVisibleBounds() throws Exception {
        String body = mockMvc.perform(get("/api/places")
                        .param("latitude", "0.0")
                        .param("longitude", "0.0")
                        .param("radiusKm", "1")
                        .param("north", "0.01")
                        .param("south", "-0.01")
                        .param("east", "0.01")
                        .param("west", "-0.01")
                        .param("mode", "restaurant")
                        .param("source", "kakaoLocal")
                        .param("limit", "20")
                        .param("includeTourApi", "false"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.fallbackUsed").value(false))
                .andExpect(jsonPath("$.cacheMiss").value(true))
                .andReturn()
                .getResponse()
                .getContentAsString();

        PlacesResponse response = objectMapper.readValue(body, PlacesResponse.class);

        assertThat(response.total()).isZero();
        assertThat(response.randomScope()).contains("source=kakaoLocal");
        assertThat(response.places()).isEmpty();
    }

    @Test
    void placesEndpointExpandsScopeWhenVisibleBoundsHaveNoCandidates() throws Exception {
        String body = mockMvc.perform(get("/api/places")
                        .param("north", "0.0")
                        .param("south", "-1.0")
                        .param("east", "0.0")
                        .param("west", "-1.0")
                        .param("limit", "5")
                        .param("includeTourApi", "false"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.fallbackUsed").value(true))
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);
        PlacesResponse response = objectMapper.readValue(body, PlacesResponse.class);

        assertThat(response.total()).isLessThanOrEqualTo(5);
        assertThat(response.places()).isNotEmpty();
        assertThat(response.randomScope()).contains("후보 부족");
        assertThat(json.path("places").get(0).path("tourApi").isNull()).isTrue();
    }

    @Test
    void recommendationsEndpointUsesModePoolAndReportsCachedCafeFallback() throws Exception {
        var tourResult = mockMvc.perform(post("/api/recommendations")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "mode": "tour",
                                  "limit": 10,
                                  "includeTourApi": false
                                }
                                """))
                .andExpect(status().isOk())
                .andReturn();

        JsonNode tourJson = objectMapper.readTree(tourResult.getResponse().getContentAsByteArray());
        assertThat(tourJson.path("fallbackUsed").asBoolean()).isFalse();
        assertThat(tourJson.path("randomScope").asText()).doesNotContain("mode 후보 부족");
        assertThat(tourJson.path("nearbyPick").path("place").path("tourApi").isNull()).isTrue();

        var cafeResult = mockMvc.perform(post("/api/recommendations")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "mode": "restaurant",
                                  "source": "kakaoLocal",
                                  "limit": 10,
                                  "includeTourApi": false
                                }
                                """))
                .andExpect(status().isOk())
                .andReturn();

        JsonNode cafeJson = objectMapper.readTree(cafeResult.getResponse().getContentAsByteArray());
        assertThat(cafeJson.path("fallbackUsed").asBoolean()).isFalse();
        assertThat(cafeJson.path("randomScope").asText()).contains("source=kakaoLocal");
        assertThat(cafeJson.path("nearbyPick").path("place").path("id").asText()).startsWith("kakao-");
        assertThat(cafeJson.path("nearbyPick").path("place").path("sourceAttribution").asText()).isEqualTo("kakaoLocal");
        assertThat(cafeJson.path("nearbyPick").path("place").path("tourApi").isNull()).isTrue();
    }

    @Test
    void placesEndpointRejectsPartialBounds() throws Exception {
        mockMvc.perform(get("/api/places")
                        .param("north", "38.0")
                        .param("south", "33.0"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void recommendationsEndpointSupportsLightweightMetadataAndRecentIds() throws Exception {
        var firstResult = mockMvc.perform(post("/api/recommendations")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "latitude": 37.5535,
                                  "longitude": 126.9221,
                                  "radiusKm": 50,
                                  "limit": 20,
                                  "includeTourApi": false
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.source.providerId").exists())
                .andExpect(jsonPath("$.randomScope").exists())
                .andReturn();

        JsonNode firstJson = objectMapper.readTree(firstResult.getResponse().getContentAsByteArray());
        String recentId = firstJson.path("nearbyPick").path("place").path("id").asText();
        assertThat(firstJson.path("nearbyPick").path("place").path("tourApi").isNull()).isTrue();

        var secondResult = mockMvc.perform(post("/api/recommendations")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "latitude": 37.5535,
                                  "longitude": 126.9221,
                                  "radiusKm": 50,
                                  "limit": 20,
                                  "recentPlaceIds": ["%s"],
                                  "includeTourApi": false
                                }
                                """.formatted(recentId)))
                .andExpect(status().isOk())
                .andReturn();

        JsonNode secondJson = objectMapper.readTree(secondResult.getResponse().getContentAsByteArray());
        assertThat(secondJson.path("nearbyPick").path("place").path("id").asText()).isNotEqualTo(recentId);
        assertThat(secondJson.path("nearbyPick").path("place").path("tourApi").isNull()).isTrue();
    }

    @Test
    void placesEndpointRejectsPartialLocation() throws Exception {
        mockMvc.perform(get("/api/places")
                        .param("latitude", "37.5665"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void searchEndpointRejectsPartialLocation() throws Exception {
        mockMvc.perform(post("/api/search")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "query": "조용한 카페",
                                  "latitude": 37.55
                                }
                                """))
                .andExpect(status().isBadRequest());
    }

    @Test
    void searchEndpointReturnsPetFriendlyResult() throws Exception {
        var mvcResult = mockMvc.perform(post("/api/search")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "query": "카페",
                                  "mode": "HYBRID",
                                  "topK": 5
                                }
                                """))
                .andExpect(status().isOk())
                .andReturn();

        SearchResponse response = objectMapper.readValue(
                mvcResult.getResponse().getContentAsByteArray(),
                SearchResponse.class
        );
        JsonNode json = objectMapper.readTree(mvcResult.getResponse().getContentAsByteArray());

        assertThat(response.results()).isNotEmpty();
        assertThat(response.source()).isNotNull();
        assertThat(response.source().providerId()).isNotBlank();
        assertThat(response.source().status()).isNotBlank();
        assertThat(response.total()).isEqualTo(response.results().size());
        assertThat(response.source().count()).isGreaterThanOrEqualTo(response.results().size());
        assertThat(json.path("results").get(0).has("tourApi")).isTrue();
    }

    @Test
    void recommendationsEndpointReturnsDiscoveryCards() throws Exception {
        var mvcResult = mockMvc.perform(post("/api/recommendations")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "latitude": 37.5535,
                                  "longitude": 126.9221,
                                  "radiusKm": 3
                                }
                                """))
                .andExpect(status().isOk())
                .andReturn();

        RecommendationResponse response = objectMapper.readValue(
                mvcResult.getResponse().getContentAsByteArray(),
                RecommendationResponse.class
        );
        JsonNode json = objectMapper.readTree(mvcResult.getResponse().getContentAsByteArray());

        assertThat(response.nearbyPick()).isNotNull();
        assertThat(response.nearbyPick().place()).isNotNull();
        assertThat(response.mealPick()).isNotNull();
        assertThat(response.mealPick().place()).isNotNull();
        assertThat(response.dateCourse()).isNotNull();
        assertThat(response.dateCourse().stops()).hasSize(3);
        assertThat(json.path("nearbyPick").path("place").has("tourApi")).isTrue();
        assertThat(json.path("mealPick").path("place").has("tourApi")).isTrue();
        assertThat(json.path("dateCourse").path("stops").get(0).path("place").has("tourApi")).isTrue();
    }

    @Test
    void themesEndpointReturnsOrderedThemeCatalog() throws Exception {
        String body = mockMvc.perform(get("/api/themes"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);

        assertThat(json.isArray()).isTrue();
        assertThat(json).isNotEmpty();
        assertThat(json.get(0).path("themeId").asText()).isEqualTo("seoul-events");
        assertThat(json.get(0).path("scope").asText()).isEqualTo("seoul");
    }

    @Test
    void themeDetailEndpointReturnsThemePlacesAndSources() throws Exception {
        String body = mockMvc.perform(get("/api/themes/{themeId}", themeId))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);

        assertThat(json.path("themeId").asText()).isEqualTo(themeId);
        assertThat(json.path("center").path("latitude").isNumber()).isTrue();
        assertThat(json.path("sourceAttributions").isArray()).isTrue();
        assertThat(json.path("places").isArray()).isTrue();
    }

    @Test
    void weakThemeStillReturnsFallbackPlacesForMapDensity() throws Exception {
        String body = mockMvc.perform(get("/api/themes/{themeId}", "nationwide-pet"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);

        assertThat(json.path("themeId").asText()).isEqualTo("nationwide-pet");
        assertThat(json.path("places").isArray()).isTrue();
        assertThat(json.path("places").size()).isGreaterThan(1);
    }

    @Test
    void seoulThemeDetailKeepsFallbackPlacesInsideSeoulScope() throws Exception {
        String body = mockMvc.perform(get("/api/themes/{themeId}", "seoul-events"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);

        assertThat(json.path("themeId").asText()).isEqualTo("seoul-events");
        assertThat(json.path("places").isArray()).isTrue();
        assertThat(json.path("places")).isNotEmpty();
        assertThat(json.path("places"))
                .allSatisfy(place -> assertThat(
                        place.path("address").asText()
                                + " "
                                + place.path("roadAddress").asText()
                                + " "
                                + place.path("district").asText()
                ).contains("서울"));
    }



    @Test
    void restaurantPlacesUseOnlyKakaoRestaurantCacheWithoutCafeLikeResults() throws Exception {
        String body = mockMvc.perform(get("/api/places")
                        .param("latitude", "37.6367")
                        .param("longitude", "127.0679")
                        .param("radiusKm", "10")
                        .param("north", "37.70")
                        .param("south", "37.60")
                        .param("east", "127.12")
                        .param("west", "127.02")
                        .param("mode", "restaurant")
                        .param("source", "kakaoLocal")
                        .param("limit", "80")
                        .param("includeTourApi", "false"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);
        JsonNode places = json.path("places");

        assertThat(json.path("randomScope").asText()).contains("source=kakaoLocal");
        assertThat(json.path("fallbackUsed").asBoolean()).isFalse();
        assertThat(places.isArray()).isTrue();
        assertThat(places.size()).isGreaterThan(0);
        assertThat(places).allSatisfy(place -> {
            String haystack = String.join(" ",
                    place.path("name").asText(),
                    place.path("category").asText(),
                    place.path("summary").asText());
            assertThat(haystack).doesNotContain(
                    "카페", "커피", "스타벅스", "투썸", "컴포즈", "메가", "빽다방", "이디야",
                    "디저트", "베이커리", "제과", "파리바게뜨", "뚜레쥬르", "도넛", "아이스크림",
                    "브런치", "샐러드", "샌드위치", "술집", "호프", "와인바", "칵테일바");
        });
    }

    @Test
    void eventsEndpointDefaultsToOnlyActiveEvents() throws Exception {
        String body = mockMvc.perform(get("/api/events")
                        .param("limit", "10"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode events = objectMapper.readTree(body).path("events");

        assertThat(events.isArray()).isTrue();
        assertThat(events).allSatisfy(event -> assertThat(event.path("status").asText()).isEqualTo("ACTIVE"));
    }

    @Test
    void eventsEndpointFiltersByThemeAndDateWithoutFailingOnEmptyResult() throws Exception {
        String body = mockMvc.perform(get("/api/events")
                        .param("themeId", themeId)
                        .param("region", "seoul")
                        .param("activeOn", "2026-04-22")
                        .param("limit", "5"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        JsonNode json = objectMapper.readTree(body);

        assertThat(json.path("events").isArray()).isTrue();
        assertThat(json.path("total").asInt()).isGreaterThanOrEqualTo(0);
    }

    @Test
    void searchEndpointSupportsThemeScopedSearch() throws Exception {
        var mvcResult = mockMvc.perform(post("/api/search")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "query": "야간 산책",
                                  "themeId": "%s",
                                  "mode": "HYBRID",
                                  "topK": 5
                                }
                                """.formatted(themeId)))
                .andExpect(status().isOk())
                .andReturn();

        SearchResponse response = objectMapper.readValue(
                mvcResult.getResponse().getContentAsByteArray(),
                SearchResponse.class
        );

        assertThat(response.themeId()).isEqualTo(themeId);
        assertThat(response.results()).hasSizeLessThanOrEqualTo(5);
    }
}

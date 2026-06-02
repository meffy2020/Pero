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

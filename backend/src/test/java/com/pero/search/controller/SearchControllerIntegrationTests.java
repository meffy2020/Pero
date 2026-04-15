package com.pero.search.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pero.search.dto.RecommendationResponse;
import com.pero.search.dto.SearchResponse;
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

    @Test
    void healthEndpointReturnsServiceStatus() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.service").value("pero-backend"))
                .andExpect(jsonPath("$.status").value("ok"));
    }

    @Test
    void placesEndpointReturnsSeedData() throws Exception {
        mockMvc.perform(get("/api/places"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(8))
                .andExpect(jsonPath("$[0].id").exists());
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
                                  "query": "반려동물과 갈 수 있는 카페",
                                  "mode": "HYBRID",
                                  "latitude": 37.5496,
                                  "longitude": 126.9134,
                                  "radiusKm": 5,
                                  "topK": 5
                                }
                                """))
                .andExpect(status().isOk())
                .andReturn();

        SearchResponse response = objectMapper.readValue(
                mvcResult.getResponse().getContentAsByteArray(),
                SearchResponse.class
        );

        assertThat(response.results()).isNotEmpty();
        assertThat(response.results().getFirst().id()).isEqualTo("place-005");
        assertThat(response.results().getFirst().tags()).contains("반려동물");
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

        assertThat(response.nearbyPick()).isNotNull();
        assertThat(response.nearbyPick().place()).isNotNull();
        assertThat(response.mealPick()).isNotNull();
        assertThat(response.mealPick().place()).isNotNull();
        assertThat(response.dateCourse()).isNotNull();
        assertThat(response.dateCourse().stops()).hasSize(3);
    }
}

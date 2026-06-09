package com.pero.search.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pero.search.dto.PlacesResponse;
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
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(
        properties = {
                "pero.providers.order=koreaTour,smartSeoul",
                "pero.providers.kakaoLocal.enabled=false",
                "pero.providers.koreaTour.enabled=true",
                "pero.providers.koreaTour.cache-resource=classpath:test-data/provider-test/places-korea-tour.json",
                "pero.providers.koreaTour.meta-resource=classpath:test-data/provider-test/places-korea-tour.meta.json",
                "pero.providers.smartSeoul.enabled=true",
                "pero.providers.smartSeoul.cache-resource=classpath:test-data/provider-test/places-smart-missing.json",
                "pero.providers.smartSeoul.meta-resource=classpath:test-data/provider-test/places-smart-missing.meta.json"
        }
)
@AutoConfigureMockMvc
class SearchControllerProviderFallbackIntegrationTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void placesAndSearchUseKoreaTourWhenSmartUnavailable() throws Exception {
        String placesBody = mockMvc.perform(get("/api/places"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        PlacesResponse placesResponse = objectMapper.readValue(placesBody, PlacesResponse.class);
        assertThat(placesResponse.source().providerId()).isEqualTo("koreaTour");
        assertThat(placesResponse.source().providerName()).contains("한국관광공사");
        assertThat(placesResponse.source().status()).isEqualTo("ok");
        assertThat(placesResponse.places()).hasSize(2);

        String searchBody = mockMvc.perform(
                        post("/api/search")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("""
                                        {
                                          "query": "조용한 카페",
                                          "latitude": 37.51,
                                          "longitude": 126.92,
                                          "radiusKm": 10,
                                          "topK": 5
                                        }
                                        """)
                )
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        SearchResponse searchResponse = objectMapper.readValue(searchBody, SearchResponse.class);
        assertThat(searchResponse.source().providerId()).isEqualTo("koreaTour");
        assertThat(searchResponse.source().status()).isEqualTo("ok");
        assertThat(searchResponse.total()).isGreaterThan(0);
    }
}

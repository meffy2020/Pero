package com.pero.search.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pero.search.dto.SearchResponse;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(
        properties = {
                "pero.providers.order=smartSeoul,koreaTour",
                "pero.providers.kakaoLocal.enabled=false",
                "pero.providers.koreaTour.enabled=true",
                "pero.providers.koreaTour.cache-resource=classpath:test-data/provider-test/places-korea-tour.json",
                "pero.providers.koreaTour.meta-resource=classpath:test-data/provider-test/places-korea-tour.meta.json",
                "pero.providers.smartSeoul.enabled=true",
                "pero.providers.smartSeoul.cache-resource=classpath:test-data/provider-test/places-smart.json",
                "pero.providers.smartSeoul.meta-resource=classpath:test-data/provider-test/places-smart.meta.json"
        }
)
@AutoConfigureMockMvc
class SearchControllerProviderSmartPrimaryIntegrationTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void searchMergesProvidersButKeepsSmartSeoulPriorityForOverlappingSeoulQueries() throws Exception {
        String body = mockMvc.perform(
                        post("/api/search")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("""
                                        {
                                          "query": "브런치",
                                          "latitude": 37.5482,
                                          "longitude": 126.9053,
                                          "radiusKm": 8,
                                          "topK": 5
                                        }
                                        """)
                )
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        SearchResponse searchResponse = objectMapper.readValue(body, SearchResponse.class);
        assertThat(searchResponse.source().providerId()).isEqualTo("smartSeoul,koreaTour");
        assertThat(searchResponse.source().providerName()).contains("스마트서울맵");
        assertThat(searchResponse.source().providerName()).contains("한국관광공사");
        assertThat(searchResponse.source().count()).isEqualTo(4);
        assertThat(searchResponse.results())
                .extracting(result -> result.sourceAttribution())
                .contains("smartSeoul");
    }
}

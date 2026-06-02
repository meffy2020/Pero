package com.pero.search.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pero.search.dto.PlacesResponse;
import com.pero.search.dto.SearchResponse;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class SearchControllerSmartSeoulIntegrationTests {

    private static final Path SMART_CACHE_PATH = writeTempFile(
            "smart-seoul-cache",
            ".json",
            """
                    [
                      {
                        "id": "smart-night-1",
                        "name": "서울야경전망대",
                        "category": "전망대",
                        "district": "중구",
                        "address": "서울 중구 세종대로 110",
                        "roadAddress": "서울 중구 세종대로 110",
                        "latitude": 37.5663,
                        "longitude": 126.9779,
                        "summary": "서울 야경 산책과 데이트에 맞는 전망대입니다.",
                        "tags": ["야경", "산책", "데이트"],
                        "searchHints": ["서울 야경 산책 질의에 맞춘 Smart Seoul 테스트 데이터입니다."]
                      },
                      {
                        "id": "smart-book-1",
                        "name": "서울책정원",
                        "category": "북카페",
                        "district": "종로구",
                        "address": "서울 종로구 세종대로 175",
                        "roadAddress": "서울 종로구 세종대로 175",
                        "latitude": 37.5720,
                        "longitude": 126.9769,
                        "summary": "조용히 머무르며 책을 읽기 좋은 북카페입니다.",
                        "tags": ["조용한", "북카페", "휴식"],
                        "searchHints": ["조용한 북카페 질의에 맞춘 Smart Seoul 테스트 데이터입니다."]
                      }
                    ]
                    """
    );

    private static final Path SMART_META_PATH = writeTempFile(
            "smart-seoul-meta",
            ".json",
            """
                    {
                      "providerId": "smartSeoul",
                      "providerName": "스마트서울맵 캐시",
                      "generatedAt": "2026-04-21T18:10:00+09:00",
                      "status": "ok",
                      "count": 2
                    }
                    """
    );

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @DynamicPropertySource
    static void registerSmartSeoulProperties(DynamicPropertyRegistry registry) {
        registry.add("pero.providers.order", () -> "smartSeoul,koreaTour");
        registry.add("pero.providers.koreaTour.enabled", () -> "false");
        registry.add("pero.providers.smartSeoul.enabled", () -> "true");
        registry.add("pero.providers.smartSeoul.cache-resource", () -> SMART_CACHE_PATH.toUri().toString());
        registry.add("pero.providers.smartSeoul.meta-resource", () -> SMART_META_PATH.toUri().toString());
    }

    @Test
    void placesEndpointUsesSmartSeoulSourceWhenEnabled() throws Exception {
        String body = mockMvc.perform(get("/api/places"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        PlacesResponse response = objectMapper.readValue(body, PlacesResponse.class);

        assertThat(response.source().providerId()).isEqualTo("smartSeoul");
        assertThat(response.source().providerName()).isEqualTo("스마트서울맵 캐시");
        assertThat(response.source().status()).isEqualTo("ok");
        assertThat(response.source().count()).isEqualTo(2);
        assertThat(response.total()).isEqualTo(2);
        assertThat(response.places())
                .extracting(place -> place.id())
                .containsExactlyInAnyOrder("smart-night-1", "smart-book-1");
    }

    @Test
    void searchEndpointUsesSmartSeoulSourceWhenEnabled() throws Exception {
        String body = mockMvc.perform(post("/api/search")
                        .contentType(APPLICATION_JSON)
                        .content("""
                                {
                                  "query": "야경 산책",
                                  "mode": "HYBRID",
                                  "topK": 5
                                }
                                """))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        SearchResponse response = objectMapper.readValue(body, SearchResponse.class);

        assertThat(response.source().providerId()).isEqualTo("smartSeoul");
        assertThat(response.source().status()).isEqualTo("ok");
        assertThat(response.source().count()).isEqualTo(2);
        assertThat(response.results()).isNotEmpty();
        assertThat(response.results())
                .extracting(result -> result.id())
                .contains("smart-night-1");
    }

    private static Path writeTempFile(String prefix, String suffix, String content) {
        try {
            Path path = Files.createTempFile(prefix, suffix);
            Files.writeString(path, content, StandardCharsets.UTF_8);
            path.toFile().deleteOnExit();
            return path;
        } catch (IOException exception) {
            throw new UncheckedIOException(exception);
        }
    }
}

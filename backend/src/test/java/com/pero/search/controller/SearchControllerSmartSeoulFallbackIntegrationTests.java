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
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class SearchControllerSmartSeoulFallbackIntegrationTests {

    private static final Path MISSING_SMART_CACHE_PATH = missingPath("smart-seoul-missing-cache", ".json");
    private static final Path MISSING_SMART_META_PATH = missingPath("smart-seoul-missing-meta", ".json");

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @DynamicPropertySource
    static void registerFallbackProperties(DynamicPropertyRegistry registry) {
        registry.add("pero.providers.order", () -> "smartSeoul,koreaTour");
        registry.add("pero.providers.smartSeoul.enabled", () -> "true");
        registry.add("pero.providers.smartSeoul.cache-resource", () -> MISSING_SMART_CACHE_PATH.toUri().toString());
        registry.add("pero.providers.smartSeoul.meta-resource", () -> MISSING_SMART_META_PATH.toUri().toString());
    }

    @Test
    void placesEndpointFallsBackToKoreaTourWhenSmartCacheMisses() throws Exception {
        String body = mockMvc.perform(get("/api/places"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        PlacesResponse response = objectMapper.readValue(body, PlacesResponse.class);

        assertThat(response.source().providerId()).isEqualTo("koreaTour");
        assertThat(response.source().status()).isNotBlank();
        assertThat(response.source().count()).isEqualTo(response.total());
        assertThat(response.total()).isGreaterThan(0);
    }

    @Test
    void searchEndpointFallsBackToKoreaTourWhenSmartCacheMisses() throws Exception {
        String body = mockMvc.perform(post("/api/search")
                        .contentType(APPLICATION_JSON)
                        .content("""
                                {
                                  "query": "카페",
                                  "mode": "HYBRID",
                                  "topK": 5
                                }
                                """))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        SearchResponse response = objectMapper.readValue(body, SearchResponse.class);

        assertThat(response.source().providerId()).isEqualTo("koreaTour");
        assertThat(response.source().status()).isNotBlank();
        assertThat(response.source().count()).isGreaterThanOrEqualTo(response.results().size());
        assertThat(response.results()).isNotEmpty();
    }

    private static Path missingPath(String prefix, String suffix) {
        try {
            Path path = Files.createTempFile(prefix, suffix);
            Files.deleteIfExists(path);
            return path;
        } catch (IOException exception) {
            throw new UncheckedIOException(exception);
        }
    }
}

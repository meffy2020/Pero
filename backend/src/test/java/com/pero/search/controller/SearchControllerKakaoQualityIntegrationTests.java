package com.pero.search.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pero.search.dto.PlacesResponse;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(
        properties = {
                "pero.providers.order=kakaoLocal",
                "pero.providers.kakaoLocal.enabled=true",
                "pero.providers.kakaoLocal.cache-resource=classpath:test-data/provider-test/places-kakao-synthetic.json",
                "pero.providers.kakaoLocal.meta-resource=classpath:test-data/provider-test/places-kakao-synthetic.meta.json",
                "pero.providers.koreaTour.enabled=false",
                "pero.providers.smartSeoul.enabled=false"
        }
)
@AutoConfigureMockMvc
class SearchControllerKakaoQualityIntegrationTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void kakaoLocalRuntimeExcludesSyntheticRestaurantEntries() throws Exception {
        String body = mockMvc.perform(get("/api/places")
                        .param("source", "kakaoLocal")
                        .param("mode", "restaurant")
                        .param("limit", "20")
                        .param("includeTourApi", "false"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        PlacesResponse response = objectMapper.readValue(body, PlacesResponse.class);

        assertThat(response.source().providerId()).isEqualTo("kakaoLocal");
        assertThat(response.places())
                .hasSize(1)
                .allSatisfy(place -> {
                    assertThat(place.name()).doesNotContain("더미");
                    assertThat(place.sourceAttribution()).isEqualTo("kakaoLocal");
                });
        assertThat(response.places().get(0).name()).isEqualTo("하계동 밥집");
    }
}

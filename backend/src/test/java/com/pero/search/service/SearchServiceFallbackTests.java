package com.pero.search.service;

import com.pero.search.data.PlaceDataLoadResult;
import com.pero.search.dto.RecommendationRequest;
import com.pero.search.dto.SearchRequest;
import com.pero.search.model.SearchMode;
import com.pero.search.repository.PlaceRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SearchServiceFallbackTests {

    @Mock
    private PlaceRepository placeRepository;

    private SearchService searchService;

    @BeforeEach
    void setUp() {
        TextNormalizer normalizer = new TextNormalizer();
        EmbeddingService embeddingService = new EmbeddingService(normalizer);
        lenient().when(placeRepository.source()).thenReturn(
                PlaceDataLoadResult.missing("koreaTour", "한국관광공사", "cache-missing")
        );
        when(placeRepository.findAll()).thenReturn(List.of());
        this.searchService = new SearchService(placeRepository, normalizer, embeddingService);
    }

    @Test
    void searchReturnsEmptyResultWhenNoCache() {
        var request = new SearchRequest(
                "조용한 카페",
                SearchMode.HYBRID,
                37.5619,
                126.9782,
                3.0,
                5
        );

        var response = searchService.search(request);

        assertThat(response.results()).isEmpty();
        assertThat(response.total()).isEqualTo(0);
        assertThat(response.source().count()).isZero();
        assertThat(response.source().status()).isEqualTo("cache-missing");
    }

    @Test
    void recommendationsReturnFallbackWithoutNpe() {
        var request = new RecommendationRequest(37.5619, 126.9782, 3.0);

        var response = searchService.recommend(request);

        assertThat(response.fallbackUsed()).isTrue();
        assertThat(response.nearbyPick().place()).isNotNull();
        assertThat(response.mealPick().place()).isNotNull();
        assertThat(response.mealPick().place().name()).isEqualTo("데이터 없음");
        assertThat(response.dateCourse().stops()).hasSize(3);
    }
}

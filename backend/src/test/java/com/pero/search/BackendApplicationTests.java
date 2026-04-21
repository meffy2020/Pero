package com.pero.search;

import com.pero.search.dto.RecommendationRequest;
import com.pero.search.dto.SearchRequest;
import com.pero.search.model.SearchMode;
import com.pero.search.service.SearchService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class BackendApplicationTests {

	@Autowired
	private SearchService searchService;

	@Test
	void contextLoads() {
		assertThat(searchService).isNotNull();
	}

	@Test
	void hybridSearchReturnsResult() {
		var request = new SearchRequest("카페", SearchMode.HYBRID, null, null, null, 5);
		var response = searchService.search(request);

		assertThat(response.results()).isNotEmpty();
		assertThat(response.total()).isPositive();
		assertThat(response.source()).isNotNull();
		assertThat(response.source().providerId()).isNotBlank();
		assertThat(response.source().status()).isNotBlank();
		assertThat(response.total()).isEqualTo(response.results().size());
		assertThat(response.source().count()).isGreaterThanOrEqualTo(response.results().size());
	}

	@Test
	void searchWithoutLocationUsesDefaults() {
		var request = new SearchRequest("조용한 북카페", null, null, null, null, null);
		var response = searchService.search(request);

		assertThat(response.mode()).isEqualTo(SearchMode.HYBRID);
		assertThat(response.topK()).isEqualTo(8);
		assertThat(response.results()).isNotEmpty();
		assertThat(response.total()).isEqualTo(response.results().size());
		assertThat(response.results())
				.extracting(result -> result.distanceKm())
				.containsOnlyNulls();
	}

	@Test
	void recommendationBuildsDateCourseWithThreeStops() {
		var request = new RecommendationRequest(37.5535, 126.9221, 5.0);
		var response = searchService.recommend(request);

		assertThat(response.nearbyPick().place()).isNotNull();
		assertThat(response.mealPick().place()).isNotNull();
		assertThat(response.dateCourse().stops()).hasSize(3);
	}

}

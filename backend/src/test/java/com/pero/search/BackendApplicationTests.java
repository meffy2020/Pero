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
	void hybridSearchReturnsPetFriendlyPlace() {
		var request = new SearchRequest("반려동물과 브런치", SearchMode.HYBRID, 37.5496, 126.9134, 5.0, 5);
		var response = searchService.search(request);

		assertThat(response.results()).isNotEmpty();
		assertThat(response.results().getFirst().tags()).contains("반려동물");
	}

	@Test
	void searchWithoutLocationUsesDefaults() {
		var request = new SearchRequest("조용한 북카페", null, null, null, null, null);
		var response = searchService.search(request);

		assertThat(response.mode()).isEqualTo(SearchMode.HYBRID);
		assertThat(response.topK()).isEqualTo(8);
		assertThat(response.results()).isNotEmpty();
		assertThat(response.results())
				.extracting(result -> result.id())
				.contains("place-001");
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
		assertThat(response.dateCourse().stops())
				.extracting(stop -> stop.place().id())
				.doesNotHaveDuplicates();
	}

}

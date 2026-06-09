package com.pero.search.controller;

import com.pero.search.dto.RecommendationRequest;
import com.pero.search.dto.RecommendationResponse;
import com.pero.search.dto.SearchRequest;
import com.pero.search.dto.SearchResponse;
import com.pero.search.dto.PlacesResponse;
import com.pero.search.dto.EventsResponse;
import com.pero.search.dto.ThemeDetailResponse;
import com.pero.search.dto.ThemeSummaryResponse;
import com.pero.search.service.SearchService;
import com.pero.search.service.ThemeMapService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class SearchController {

    private final SearchService searchService;
    private final ThemeMapService themeMapService;

    public SearchController(SearchService searchService, ThemeMapService themeMapService) {
        this.searchService = searchService;
        this.themeMapService = themeMapService;
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        return Map.of(
                "service", "pero-backend",
                "status", "ok",
                "time", OffsetDateTime.now()
        );
    }

    @GetMapping("/places")
    public PlacesResponse places(
            @RequestParam(required = false) Double latitude,
            @RequestParam(required = false) Double longitude,
            @RequestParam(required = false) Double radiusKm,
            @RequestParam(required = false) Integer limit,
            @RequestParam(defaultValue = "true") boolean includeTourApi
    ) {
        return searchService.places(latitude, longitude, radiusKm, limit, includeTourApi);
    }

    @GetMapping("/themes")
    public List<ThemeSummaryResponse> themes() {
        return themeMapService.themes();
    }

    @GetMapping("/themes/{themeId}")
    public ThemeDetailResponse theme(@PathVariable String themeId) {
        return themeMapService.theme(themeId);
    }

    @GetMapping("/events")
    public EventsResponse events(
            @RequestParam(required = false) String region,
            @RequestParam(required = false) String themeId,
            @RequestParam(required = false) LocalDate activeOn,
            @RequestParam(required = false) Integer limit
    ) {
        return themeMapService.events(region, themeId, activeOn, limit);
    }

    @PostMapping("/search")
    public SearchResponse search(@Valid @RequestBody SearchRequest request) {
        return searchService.search(request);
    }

    @PostMapping("/recommendations")
    public RecommendationResponse recommend(@Valid @RequestBody RecommendationRequest request) {
        return searchService.recommend(request);
    }
}

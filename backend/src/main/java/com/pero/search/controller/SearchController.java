package com.pero.search.controller;

import com.pero.search.dto.SearchRequest;
import com.pero.search.dto.SearchResponse;
import com.pero.search.service.SearchService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class SearchController {

    private final SearchService searchService;

    public SearchController(SearchService searchService) {
        this.searchService = searchService;
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
    public List<Map<String, Object>> places() {
        return searchService.getPlaces();
    }

    @PostMapping("/search")
    public SearchResponse search(@Valid @RequestBody SearchRequest request) {
        return searchService.search(request);
    }
}

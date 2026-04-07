package com.lumo.search.dto;

import com.lumo.search.model.SearchMode;

import java.time.OffsetDateTime;
import java.util.List;

public record SearchResponse(
        String query,
        SearchMode mode,
        int total,
        int topK,
        OffsetDateTime generatedAt,
        List<PlaceResultResponse> results
) {
}

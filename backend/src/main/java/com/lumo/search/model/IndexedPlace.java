package com.lumo.search.model;

import java.util.List;
import java.util.Map;
import java.util.Set;

public record IndexedPlace(
        String id,
        String name,
        String category,
        String district,
        String address,
        String roadAddress,
        double latitude,
        double longitude,
        String summary,
        List<String> tags,
        List<IndexedReview> reviews,
        Map<String, Integer> termFrequencies,
        Set<String> featureTokens,
        int documentLength,
        double[] embedding
) {
}

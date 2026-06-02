package com.pero.search.dto;

import java.util.List;

public record RecommendationPlaceResponse(
        String id,
        String name,
        String category,
        String district,
        String roadAddress,
        String summary,
        List<String> tags,
        List<String> themeTags,
        double latitude,
        double longitude,
        String sourceAttribution,
        Double distanceKm,
        String reason,
        TourApiResponse tourApi
) {
}

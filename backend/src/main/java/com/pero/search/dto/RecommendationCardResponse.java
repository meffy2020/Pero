package com.pero.search.dto;

public record RecommendationCardResponse(
        String key,
        String title,
        String description,
        RecommendationPlaceResponse place
) {
}

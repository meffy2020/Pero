package com.pero.search.dto;

import java.util.List;

public record PlaceListItemResponse(
        String id,
        String name,
        String category,
        String district,
        String address,
        String roadAddress,
        String summary,
        List<String> tags,
        List<String> themeTags,
        double latitude,
        double longitude,
        String sourceAttribution,
        TourApiResponse tourApi
) {
}

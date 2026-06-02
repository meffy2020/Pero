package com.pero.search.dto;

import java.util.List;

public record PlaceResultResponse(
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
        Double distanceKm,
        String evidence,
        double keywordScore,
        double vectorScore,
        double featureScore,
        double geoScore,
        double finalScore,
        TourApiResponse tourApi
) {
}

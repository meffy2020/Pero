package com.lumo.search.dto;

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
        double latitude,
        double longitude,
        Double distanceKm,
        String evidence,
        double keywordScore,
        double vectorScore,
        double featureScore,
        double geoScore,
        double finalScore
) {
}

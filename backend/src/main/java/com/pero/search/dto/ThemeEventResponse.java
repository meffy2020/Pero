package com.pero.search.dto;

public record ThemeEventResponse(
        String id,
        String title,
        String status,
        String startDate,
        String endDate,
        String periodLabel,
        String district,
        String venue,
        double latitude,
        double longitude,
        String sourceAttribution,
        String summary,
        String themeId,
        String relatedPlaceId
) {
}

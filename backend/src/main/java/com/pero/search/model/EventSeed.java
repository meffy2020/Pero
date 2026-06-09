package com.pero.search.model;

import java.time.LocalDate;

public record EventSeed(
        String id,
        String title,
        LocalDate startDate,
        LocalDate endDate,
        String district,
        String venue,
        double latitude,
        double longitude,
        String summary,
        String sourceAttribution,
        String officialUrl,
        String relatedPlaceId
) {
}

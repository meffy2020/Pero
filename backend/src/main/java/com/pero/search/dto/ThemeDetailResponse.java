package com.pero.search.dto;

import java.time.OffsetDateTime;
import java.util.List;

public record ThemeDetailResponse(
        String themeId,
        String title,
        String scope,
        String source,
        String badge,
        String summary,
        OffsetDateTime generatedAt,
        ThemeCenterResponse center,
        boolean smartSeoulLayerEnabled,
        List<String> sourceAttributions,
        List<ThemePlaceResponse> places,
        List<ThemeEventResponse> events
) {
}

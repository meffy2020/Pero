package com.pero.search.dto;

import java.util.List;

public record ThemeSummaryResponse(
        String themeId,
        String title,
        String scope,
        String source,
        String badge,
        String summary,
        List<ThemePlaceResponse> heroPlaces,
        int heroEventCount
) {
}

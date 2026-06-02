package com.pero.search.model;

public record ThemeSeed(
        String themeId,
        String title,
        String scope,
        String source,
        String badge,
        String summary,
        double latitude,
        double longitude,
        boolean smartSeoulLayerEnabled,
        int priority
) {
}

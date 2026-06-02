package com.pero.search.model;

public record ThemePlaceLink(
        String themeId,
        String placeId,
        String reason,
        double weight
) {
}

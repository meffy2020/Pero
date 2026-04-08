package com.pero.search.model;

import java.util.List;

public record PlaceSeed(
        String id,
        String name,
        String category,
        String district,
        String address,
        String roadAddress,
        double latitude,
        double longitude,
        String summary,
        List<String> tags,
        List<String> searchHints
) {
}

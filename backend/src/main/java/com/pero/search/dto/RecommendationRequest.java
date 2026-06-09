package com.pero.search.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Positive;

import java.util.List;

public record RecommendationRequest(
        String themeId,

        @DecimalMin(value = "-90.0", message = "latitude는 -90 이상이어야 합니다.")
        @DecimalMax(value = "90.0", message = "latitude는 90 이하여야 합니다.")
        Double latitude,

        @DecimalMin(value = "-180.0", message = "longitude는 -180 이상이어야 합니다.")
        @DecimalMax(value = "180.0", message = "longitude는 180 이하여야 합니다.")
        Double longitude,

        @Positive(message = "radiusKm는 양수여야 합니다.")
        Double radiusKm,

        @DecimalMin(value = "-90.0", message = "north는 -90 이상이어야 합니다.")
        @DecimalMax(value = "90.0", message = "north는 90 이하여야 합니다.")
        Double north,

        @DecimalMin(value = "-90.0", message = "south는 -90 이상이어야 합니다.")
        @DecimalMax(value = "90.0", message = "south는 90 이하여야 합니다.")
        Double south,

        @DecimalMin(value = "-180.0", message = "east는 -180 이상이어야 합니다.")
        @DecimalMax(value = "180.0", message = "east는 180 이하여야 합니다.")
        Double east,

        @DecimalMin(value = "-180.0", message = "west는 -180 이상이어야 합니다.")
        @DecimalMax(value = "180.0", message = "west는 180 이하여야 합니다.")
        Double west,

        Double zoom,
        String density,
        String category,
        String mode,
        String source,
        Integer limit,
        List<String> recentPlaceIds,
        Boolean includeTourApi
) {
    public RecommendationRequest(String themeId, Double latitude, Double longitude, Double radiusKm) {
        this(themeId, latitude, longitude, radiusKm, null, null, null, null, null, null, null, null, null, null, List.of(), true);
    }

    public double resolvedRadiusKm() {
        return radiusKm == null ? 3.0 : radiusKm;
    }

    public int resolvedLimit() {
        if (limit == null) {
            return 20;
        }
        return Math.max(1, Math.min(limit, 100));
    }

    public List<String> resolvedRecentPlaceIds() {
        return recentPlaceIds == null ? List.of() : recentPlaceIds;
    }

    public boolean shouldIncludeTourApi() {
        return includeTourApi == null || includeTourApi;
    }

    public boolean hasBounds() {
        return north != null && south != null && east != null && west != null;
    }
}

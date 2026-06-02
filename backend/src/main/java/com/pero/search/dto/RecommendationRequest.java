package com.pero.search.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Positive;

public record RecommendationRequest(
        String themeId,

        @DecimalMin(value = "-90.0", message = "latitude는 -90 이상이어야 합니다.")
        @DecimalMax(value = "90.0", message = "latitude는 90 이하여야 합니다.")
        Double latitude,

        @DecimalMin(value = "-180.0", message = "longitude는 -180 이상이어야 합니다.")
        @DecimalMax(value = "180.0", message = "longitude는 180 이하여야 합니다.")
        Double longitude,

        @Positive(message = "radiusKm는 양수여야 합니다.")
        Double radiusKm
) {
    public double resolvedRadiusKm() {
        return radiusKm == null ? 3.0 : radiusKm;
    }
}

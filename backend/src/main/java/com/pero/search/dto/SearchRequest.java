package com.pero.search.dto;

import com.pero.search.model.SearchMode;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;

public record SearchRequest(
        @NotBlank(message = "query는 비어 있을 수 없습니다.")
        String query,

        SearchMode mode,

        @DecimalMin(value = "-90.0", message = "latitude는 -90 이상이어야 합니다.")
        @DecimalMax(value = "90.0", message = "latitude는 90 이하여야 합니다.")
        Double latitude,

        @DecimalMin(value = "-180.0", message = "longitude는 -180 이상이어야 합니다.")
        @DecimalMax(value = "180.0", message = "longitude는 180 이하여야 합니다.")
        Double longitude,

        @Positive(message = "radiusKm는 양수여야 합니다.")
        Double radiusKm,

        @Min(value = 1, message = "topK는 1 이상이어야 합니다.")
        @Max(value = 20, message = "topK는 20 이하여야 합니다.")
        Integer topK
) {
    public SearchMode resolvedMode() {
        return mode == null ? SearchMode.HYBRID : mode;
    }

    public int resolvedTopK() {
        return topK == null ? 8 : topK;
    }

    public double resolvedRadiusKm() {
        return radiusKm == null ? 6.0 : radiusKm;
    }

    public boolean hasLocation() {
        return latitude != null && longitude != null;
    }
}

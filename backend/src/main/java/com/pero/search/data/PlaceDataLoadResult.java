package com.pero.search.data;

import com.pero.search.model.PlaceSeed;

import java.time.OffsetDateTime;
import java.util.List;

public record PlaceDataLoadResult(
        String providerId,
        String providerName,
        OffsetDateTime generatedAt,
        String sourceStatus,
        List<PlaceSeed> places
) {

    public static PlaceDataLoadResult disabled(String providerId, String providerName) {
        return new PlaceDataLoadResult(providerId, providerName, null, "disabled", List.of());
    }

    public static PlaceDataLoadResult missing(String providerId, String providerName, String status) {
        return new PlaceDataLoadResult(providerId, providerName, null, status, List.of());
    }

    public static PlaceDataLoadResult loaded(
            String providerId,
            String providerName,
            OffsetDateTime generatedAt,
            String status,
            List<PlaceSeed> places
    ) {
        return new PlaceDataLoadResult(providerId, providerName, generatedAt, status, List.copyOf(places));
    }
}


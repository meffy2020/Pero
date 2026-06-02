package com.pero.search.data;

import com.pero.search.model.PlaceSeed;

import java.time.OffsetDateTime;
import java.util.List;

public record PlaceDataLoadResult(
        String providerId,
        String providerName,
        OffsetDateTime generatedAt,
        String sourceStatus,
        int count,
        List<PlaceSeed> places
) {

    public static PlaceDataLoadResult disabled(String providerId, String providerName) {
        return new PlaceDataLoadResult(providerId, providerName, null, "disabled", 0, List.of());
    }

    public static PlaceDataLoadResult missing(String providerId, String providerName, String status) {
        return new PlaceDataLoadResult(providerId, providerName, null, status, 0, List.of());
    }

    public static PlaceDataLoadResult loaded(
            String providerId,
            String providerName,
            OffsetDateTime generatedAt,
            String status,
            int count,
            List<PlaceSeed> places
    ) {
        return new PlaceDataLoadResult(providerId, providerName, generatedAt, status, count, List.copyOf(places));
    }

    public boolean hasPlaces() {
        return !places.isEmpty();
    }
}

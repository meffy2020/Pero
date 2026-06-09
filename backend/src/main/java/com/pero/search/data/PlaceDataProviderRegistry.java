package com.pero.search.data;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.pero.search.model.PlaceSeed;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

@Component
public class PlaceDataProviderRegistry {

    private static final String DEFAULT_ORDER = "kakaoLocal,smartSeoul,koreaTour";

    private final Map<String, PlaceDataProvider> providers;
    private final List<String> orderedProviderIds;

    public PlaceDataProviderRegistry(
            List<PlaceDataProvider> providers,
            @Value("${pero.providers.order:" + DEFAULT_ORDER + "}") String providerOrder
    ) {
        Map<String, PlaceDataProvider> indexed = new LinkedHashMap<>();
        for (PlaceDataProvider provider : providers) {
            indexed.put(provider.id().toLowerCase(Locale.ROOT), provider);
        }

        this.providers = Map.copyOf(indexed);
        this.orderedProviderIds = parseProviderOrder(providerOrder, indexed.keySet());
    }

    public PlaceDataLoadResult loadActiveData() {
        List<PlaceDataLoadResult> enabledResults = new ArrayList<>();
        List<PlaceDataLoadResult> resultsWithPlaces = new ArrayList<>();

        for (String providerId : orderedProviderIds) {
            PlaceDataProvider provider = providers.get(providerId);
            if (provider == null || !provider.isEnabled()) {
                continue;
            }

            PlaceDataLoadResult loaded = provider.load();
            enabledResults.add(loaded);
            if (loaded.hasPlaces()) {
                resultsWithPlaces.add(loaded);
            }
        }

        if (resultsWithPlaces.size() > 1) {
            return mergeResults(resultsWithPlaces);
        }
        if (resultsWithPlaces.size() == 1) {
            return resultsWithPlaces.getFirst();
        }
        if (!enabledResults.isEmpty()) {
            return enabledResults.getFirst();
        }

        if (!providers.isEmpty()) {
            PlaceDataProvider fallback = providers.values().iterator().next();
            return fallback.load();
        }

        return PlaceDataLoadResult.missing("none", "미지정", "no-provider");
    }

    private PlaceDataLoadResult mergeResults(List<PlaceDataLoadResult> results) {
        List<PlaceSeed> mergedPlaces = new ArrayList<>();
        Set<String> seenSignatures = new LinkedHashSet<>();
        List<String> providerIds = new ArrayList<>();
        List<String> providerNames = new ArrayList<>();
        OffsetDateTime generatedAt = null;
        boolean hasDegradedSource = false;

        for (PlaceDataLoadResult result : results) {
            providerIds.add(result.providerId());
            providerNames.add(result.providerName());
            generatedAt = latest(generatedAt, result.generatedAt());
            if (!"ok".equals(result.sourceStatus())) {
                hasDegradedSource = true;
            }

            for (PlaceSeed place : result.places()) {
                String signature = signature(place);
                if (!seenSignatures.add(signature)) {
                    continue;
                }
                mergedPlaces.add(place);
            }
        }

        String status = mergedPlaces.isEmpty()
                ? (hasDegradedSource ? "empty-partial" : "empty")
                : (hasDegradedSource ? "partial" : "ok");

        return PlaceDataLoadResult.loaded(
                String.join(",", providerIds),
                String.join(" + ", providerNames),
                generatedAt,
                status,
                mergedPlaces.size(),
                mergedPlaces
        );
    }

    private static OffsetDateTime latest(OffsetDateTime left, OffsetDateTime right) {
        if (left == null) {
            return right;
        }
        if (right == null) {
            return left;
        }
        return right.isAfter(left) ? right : left;
    }

    private static String signature(PlaceSeed place) {
        return String.join(
                "|",
                normalize(place.name()),
                normalize(place.address()),
                String.format(Locale.ROOT, "%.4f", place.latitude()),
                String.format(Locale.ROOT, "%.4f", place.longitude())
        );
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
    }

    private static List<String> parseProviderOrder(String providerOrder, java.util.Set<String> knownIds) {
        List<String> ordered = new ArrayList<>();
        for (String token : providerOrder.split(",")) {
            String normalized = token.trim();
            if (!normalized.isEmpty()) {
                normalized = normalized.toLowerCase(Locale.ROOT);
                if (knownIds.contains(normalized)) {
                    ordered.add(normalized);
                }
            }
        }
        for (String knownId : knownIds) {
            if (!ordered.contains(knownId)) {
                ordered.add(knownId);
            }
        }
        return ordered;
    }
}

package com.pero.search.data;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

@Component
public class PlaceDataProviderRegistry {

    private static final String DEFAULT_ORDER = "koreaTour,smartSeoul";

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
        for (String providerId : orderedProviderIds) {
            PlaceDataProvider provider = providers.get(providerId);
            if (provider == null || !provider.isEnabled()) {
                continue;
            }

            PlaceDataLoadResult loaded = provider.load();
            if (loaded.places().size() > 0) {
                return loaded;
            }
        }

        for (String providerId : orderedProviderIds) {
            PlaceDataProvider provider = providers.get(providerId);
            if (provider == null || !provider.isEnabled()) {
                continue;
            }
            return provider.load();
        }

        if (!providers.isEmpty()) {
            PlaceDataProvider fallback = providers.values().iterator().next();
            return fallback.load();
        }

        return PlaceDataLoadResult.missing("none", "미지정", "no-provider");
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

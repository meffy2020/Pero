package com.pero.search.data;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pero.search.model.PlaceSeed;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;

import java.io.IOException;
import java.io.InputStream;
import java.time.OffsetDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Map;

public abstract class AbstractCachedPlaceDataProvider implements PlaceDataProvider {

    private static final Logger log = LoggerFactory.getLogger(AbstractCachedPlaceDataProvider.class);

    private final ObjectMapper objectMapper;
    private final ResourceLoader resourceLoader;
    private final String cacheResourceLocation;
    private final String metadataResourceLocation;
    private final boolean enabled;
    private final String providerId;
    private final String providerName;

    protected AbstractCachedPlaceDataProvider(
            ObjectMapper objectMapper,
            ResourceLoader resourceLoader,
            boolean enabled,
            String providerId,
            String providerName,
            String cacheResourceLocation,
            String metadataResourceLocation
    ) {
        this.objectMapper = objectMapper;
        this.resourceLoader = resourceLoader;
        this.enabled = enabled;
        this.providerId = providerId;
        this.providerName = providerName;
        this.cacheResourceLocation = cacheResourceLocation;
        this.metadataResourceLocation = metadataResourceLocation;
    }

    @Override
    public String id() {
        return providerId;
    }

    @Override
    public String providerName() {
        return providerName;
    }

    @Override
    public boolean isEnabled() {
        return enabled;
    }

    @Override
    public PlaceDataLoadResult load() {
        if (!isEnabled()) {
            return PlaceDataLoadResult.disabled(providerId, providerName);
        }

        Resource cacheResource = resourceLoader.getResource(cacheResourceLocation);
        if (!cacheResource.exists()) {
            log.warn("캐시 파일을 찾을 수 없습니다. provider={}, path={}", providerId, cacheResourceLocation);
            return PlaceDataLoadResult.missing(providerId, providerName, "cache-missing");
        }

        CacheMetadata metadata = readMetadata();
        try (InputStream inputStream = cacheResource.getInputStream()) {
            List<PlaceSeed> places = objectMapper.readValue(
                    inputStream,
                    new TypeReference<>() {
                    }
            );
            List<PlaceSeed> normalized = sortAndDeduplicate(places).stream()
                    .map(place -> ensureSourceAttribution(place, providerId))
                    .toList();
            String resolvedProviderName = metadata.providerName() == null || metadata.providerName().isBlank()
                    ? providerName
                    : metadata.providerName();
            String status = metadata.status() == null || metadata.status().isBlank()
                    ? (normalized.isEmpty() ? "empty-cache" : "ok")
                    : metadata.status();
            int count = metadata.count() == null ? normalized.size() : metadata.count();
            return PlaceDataLoadResult.loaded(providerId, resolvedProviderName, metadata.generatedAt(), status, count, normalized);
        } catch (IOException exception) {
            log.error("캐시 파일 파싱 실패. provider={}, path={}", providerId, cacheResourceLocation, exception);
            return PlaceDataLoadResult.missing(providerId, providerName, "parse-error");
        }
    }

    private CacheMetadata readMetadata() {
        Resource metaResource = resourceLoader.getResource(metadataResourceLocation);
        if (metaResource.exists()) {
            try (InputStream inputStream = metaResource.getInputStream()) {
                Map<String, Object> payload = objectMapper.readValue(
                        inputStream,
                        new TypeReference<>() {
                        }
                );
                return new CacheMetadata(
                        payload.get("providerName") == null ? null : payload.get("providerName").toString(),
                        parseGeneratedAt(payload.get("generatedAt")),
                        payload.get("status") == null ? null : payload.get("status").toString(),
                        parseCount(payload.get("count"))
                );
            } catch (Exception exception) {
                log.warn("메타데이터 파싱 실패. provider={}, path={}", providerId, metadataResourceLocation, exception);
                return CacheMetadata.empty();
            }
        }

        return CacheMetadata.empty();
    }

    private OffsetDateTime parseGeneratedAt(Object generatedAtValue) {
        if (generatedAtValue == null) {
            return null;
        }
        return OffsetDateTime.parse(generatedAtValue.toString());
    }

    private Integer parseCount(Object countValue) {
        if (countValue == null) {
            return null;
        }
        if (countValue instanceof Number number) {
            return number.intValue();
        }
        return Integer.parseInt(countValue.toString());
    }

    protected List<PlaceSeed> sortAndDeduplicate(List<PlaceSeed> places) {
        return places == null ? Collections.emptyList() : places.stream()
                .distinct()
                .toList();
    }

    private PlaceSeed ensureSourceAttribution(PlaceSeed place, String fallbackSourceAttribution) {
        if (place == null || (place.sourceAttribution() != null && !place.sourceAttribution().isBlank())) {
            return place;
        }
        return new PlaceSeed(
                place.id(),
                place.name(),
                place.category(),
                place.district(),
                place.address(),
                place.roadAddress(),
                place.latitude(),
                place.longitude(),
                place.summary(),
                place.tags(),
                place.themeTags(),
                place.searchHints(),
                fallbackSourceAttribution,
                place.tourApi()
        );
    }

    private record CacheMetadata(
            String providerName,
            OffsetDateTime generatedAt,
            String status,
            Integer count
    ) {
        private static CacheMetadata empty() {
            return new CacheMetadata(null, null, null, null);
        }
    }
}

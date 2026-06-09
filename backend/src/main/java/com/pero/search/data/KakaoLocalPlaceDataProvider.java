package com.pero.search.data;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pero.search.model.PlaceSeed;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Locale;

@Component
public class KakaoLocalPlaceDataProvider extends AbstractCachedPlaceDataProvider {

    private static final Logger log = LoggerFactory.getLogger(KakaoLocalPlaceDataProvider.class);

    private static final String PROVIDER_ID = "kakaoLocal";
    private static final String PROVIDER_NAME = "카카오 로컬 API 캐시";
    private static final List<String> SYNTHETIC_MARKERS = List.of(
            "더미",
            "dummy",
            "fake",
            "mock",
            "시뮬레이션",
            "simulation"
    );

    public KakaoLocalPlaceDataProvider(
            ObjectMapper objectMapper,
            ResourceLoader resourceLoader,
            @Value("${pero.providers.kakaoLocal.enabled:true}") boolean enabled,
            @Value("${pero.providers.kakaoLocal.cache-resource:classpath:data/places.kakao.json}") String cacheResourceLocation,
            @Value("${pero.providers.kakaoLocal.meta-resource:classpath:data/places.kakao.json.meta.json}") String metadataResourceLocation
    ) {
        super(
                objectMapper,
                resourceLoader,
                enabled,
                PROVIDER_ID,
                PROVIDER_NAME,
                cacheResourceLocation,
                metadataResourceLocation
        );
    }

    @Override
    protected List<PlaceSeed> sortAndDeduplicate(List<PlaceSeed> places) {
        List<PlaceSeed> deduplicated = super.sortAndDeduplicate(places);
        List<PlaceSeed> filtered = deduplicated.stream()
                .filter(place -> !looksSynthetic(place))
                .toList();
        int removed = deduplicated.size() - filtered.size();
        if (removed > 0) {
            log.warn("카카오 로컬 캐시에서 synthetic 후보를 제외했습니다. removed={}", removed);
        }
        return filtered;
    }

    private boolean looksSynthetic(PlaceSeed place) {
        if (place == null) {
            return true;
        }
        String text = String.join(
                " ",
                safe(place.name()),
                safe(place.summary()),
                join(place.searchHints())
        ).toLowerCase(Locale.ROOT);
        return SYNTHETIC_MARKERS.stream()
                .map(marker -> marker.toLowerCase(Locale.ROOT))
                .anyMatch(text::contains);
    }

    private String safe(String value) {
        return value == null ? "" : value;
    }

    private String join(List<String> values) {
        return values == null ? "" : String.join(" ", values);
    }
}

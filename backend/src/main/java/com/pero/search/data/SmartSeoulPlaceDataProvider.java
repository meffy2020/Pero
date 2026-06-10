package com.pero.search.data;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pero.search.model.PlaceSeed;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
public class SmartSeoulPlaceDataProvider extends AbstractCachedPlaceDataProvider {

    private static final Logger log = LoggerFactory.getLogger(SmartSeoulPlaceDataProvider.class);

    private static final String PROVIDER_ID = "smartSeoul";
    private static final String PROVIDER_NAME = "스마트서울맵 캐시";
    private static final String ACCESSIBILITY_TRAIL_THEME = "이동약자 산책로 지도";

    public SmartSeoulPlaceDataProvider(
            ObjectMapper objectMapper,
            ResourceLoader resourceLoader,
            @Value("${pero.providers.smartSeoul.enabled:true}") boolean enabled,
            @Value("${pero.providers.smartSeoul.cache-resource:classpath:data/places.smartseoul.json}") String cacheResourceLocation,
            @Value("${pero.providers.smartSeoul.meta-resource:classpath:data/places.smartseoul.json.meta.json}") String metadataResourceLocation
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
                .filter(place -> !looksLikeAccessibilityTrailLayer(place))
                .toList();
        int removed = deduplicated.size() - filtered.size();
        if (removed > 0) {
            log.warn("스마트서울맵 캐시에서 관광 후보가 아닌 이동약자 산책로 레이어를 제외했습니다. removed={}", removed);
        }
        return filtered;
    }

    private boolean looksLikeAccessibilityTrailLayer(PlaceSeed place) {
        if (place == null) {
            return true;
        }
        String text = String.join(
                " ",
                safe(place.name()),
                safe(place.category()),
                safe(place.summary()),
                join(place.tags()),
                join(place.themeTags()),
                join(place.searchHints())
        );
        return ACCESSIBILITY_TRAIL_THEME.equals(place.category())
                || text.contains(ACCESSIBILITY_TRAIL_THEME)
                || (text.contains("보행약자") && text.contains("추천 길"))
                || (text.contains("휠체어") && text.contains("유모차") && text.contains("산책"));
    }

    private String safe(String value) {
        return value == null ? "" : value;
    }

    private String join(List<String> values) {
        return values == null ? "" : String.join(" ", values);
    }
}

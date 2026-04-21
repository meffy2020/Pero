package com.pero.search.data;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;

@Component
public class KoreaTourPlaceDataProvider extends AbstractCachedPlaceDataProvider {

    private static final String PROVIDER_ID = "koreaTour";
    private static final String PROVIDER_NAME = "한국관광공사 API 동기화 캐시";

    public KoreaTourPlaceDataProvider(
            ObjectMapper objectMapper,
            ResourceLoader resourceLoader,
            @Value("${pero.providers.koreaTour.enabled:true}") boolean enabled,
            @Value("${pero.providers.koreaTour.cache-resource:classpath:data/places.json}") String cacheResourceLocation,
            @Value("${pero.providers.koreaTour.meta-resource:classpath:data/places.json.meta.json}") String metadataResourceLocation
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
}


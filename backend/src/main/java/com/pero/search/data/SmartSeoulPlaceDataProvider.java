package com.pero.search.data;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;

@Component
public class SmartSeoulPlaceDataProvider extends AbstractCachedPlaceDataProvider {

    private static final String PROVIDER_ID = "smartSeoul";
    private static final String PROVIDER_NAME = "스마트서울맵 캐시";

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
}


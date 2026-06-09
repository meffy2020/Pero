package com.pero.search.data;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;

@Component
public class KakaoLocalPlaceDataProvider extends AbstractCachedPlaceDataProvider {

    private static final String PROVIDER_ID = "kakaoLocal";
    private static final String PROVIDER_NAME = "카카오 로컬 API 캐시";

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
}

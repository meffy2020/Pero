package com.pero.search.data;

import com.pero.search.model.PlaceSeed;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class PlaceDataProviderRegistryTests {

    @Test
    void prefersSmartSeoulWhenEnabledAndOrderedFirst() {
        PlaceDataProviderRegistry registry = new PlaceDataProviderRegistry(
                List.of(
                        provider("smartSeoul", true, PlaceDataLoadResult.loaded(
                                "smartSeoul",
                                "스마트서울맵 캐시",
                                null,
                                "ok",
                                List.of(place("smart-1", "서울야경전망대"))
                        )),
                        provider("koreaTour", true, PlaceDataLoadResult.loaded(
                                "koreaTour",
                                "한국관광공사 API 동기화 캐시",
                                null,
                                "ok",
                                List.of(place("tour-1", "홍대산책길"))
                        ))
                ),
                "smartSeoul,koreaTour"
        );

        PlaceDataLoadResult selected = registry.loadActiveData();

        assertThat(selected.providerId()).isEqualTo("smartSeoul");
        assertThat(selected.sourceStatus()).isEqualTo("ok");
        assertThat(selected.places())
                .extracting(PlaceSeed::id)
                .containsExactly("smart-1");
    }

    @Test
    void fallsBackToKoreaTourWhenSmartSeoulCacheMisses() {
        PlaceDataProviderRegistry registry = new PlaceDataProviderRegistry(
                List.of(
                        provider("smartSeoul", true, PlaceDataLoadResult.missing(
                                "smartSeoul",
                                "스마트서울맵 캐시",
                                "cache-missing"
                        )),
                        provider("koreaTour", true, PlaceDataLoadResult.loaded(
                                "koreaTour",
                                "한국관광공사 API 동기화 캐시",
                                null,
                                "ok",
                                List.of(
                                        place("tour-1", "홍대산책길"),
                                        place("tour-2", "연남북카페")
                                )
                        ))
                ),
                "smartSeoul,koreaTour"
        );

        PlaceDataLoadResult selected = registry.loadActiveData();

        assertThat(selected.providerId()).isEqualTo("koreaTour");
        assertThat(selected.sourceStatus()).isEqualTo("ok");
        assertThat(selected.places()).hasSize(2);
    }

    @Test
    void skipsSmartSeoulWhenToggleIsDisabled() {
        PlaceDataProviderRegistry registry = new PlaceDataProviderRegistry(
                List.of(
                        provider("smartSeoul", false, PlaceDataLoadResult.loaded(
                                "smartSeoul",
                                "스마트서울맵 캐시",
                                null,
                                "ok",
                                List.of(place("smart-1", "서울야경전망대"))
                        )),
                        provider("koreaTour", true, PlaceDataLoadResult.loaded(
                                "koreaTour",
                                "한국관광공사 API 동기화 캐시",
                                null,
                                "ok",
                                List.of(place("tour-1", "홍대산책길"))
                        ))
                ),
                "smartSeoul,koreaTour"
        );

        PlaceDataLoadResult selected = registry.loadActiveData();

        assertThat(selected.providerId()).isEqualTo("koreaTour");
        assertThat(selected.places())
                .extracting(PlaceSeed::id)
                .containsExactly("tour-1");
    }

    private static PlaceDataProvider provider(String id, boolean enabled, PlaceDataLoadResult result) {
        return new PlaceDataProvider() {
            @Override
            public String id() {
                return id;
            }

            @Override
            public String providerName() {
                return result.providerName();
            }

            @Override
            public boolean isEnabled() {
                return enabled;
            }

            @Override
            public PlaceDataLoadResult load() {
                return result;
            }
        };
    }

    private static PlaceSeed place(String id, String name) {
        return new PlaceSeed(
                id,
                name,
                "카페",
                "서울",
                "서울특별시 어딘가",
                "서울특별시 어딘가 1",
                37.5665,
                126.9780,
                name + " 테스트 데이터",
                List.of("테스트"),
                List.of(name + " 검색 힌트")
        );
    }
}

package com.pero.search.service;

import com.pero.search.dto.DateCourseResponse;
import com.pero.search.dto.DateCourseStopResponse;
import com.pero.search.dto.PlaceListItemResponse;
import com.pero.search.dto.PlaceResultResponse;
import com.pero.search.dto.RecommendationCardResponse;
import com.pero.search.dto.RecommendationPlaceResponse;
import com.pero.search.dto.RecommendationRequest;
import com.pero.search.dto.RecommendationResponse;
import com.pero.search.dto.SearchRequest;
import com.pero.search.dto.SearchResponse;
import com.pero.search.dto.PlacesResponse;
import com.pero.search.dto.SearchSourceMeta;
import com.pero.search.dto.TourApiResponse;
import com.pero.search.dto.TourCommonResponse;
import com.pero.search.dto.TourImageResponse;
import com.pero.search.dto.TourPetResponse;
import com.pero.search.data.PlaceDataLoadResult;
import com.pero.search.model.IndexedPlace;
import com.pero.search.model.IndexedEvidence;
import com.pero.search.model.TourApiSeed;
import com.pero.search.repository.PlaceRepository;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ThreadLocalRandom;

import static org.springframework.http.HttpStatus.BAD_REQUEST;

@Service
public class SearchService {

    private static final double BM25_K1 = 1.5;
    private static final double BM25_B = 0.75;
    private static final double RRF_CONSTANT = 60.0;
    private static final int MAX_PLACES_LIMIT = 500;
    private static final int LOW_ZOOM_MARKER_LIMIT = 80;
    private static final int MAX_RECOMMENDATION_LIMIT = 100;

    private final PlaceRepository placeRepository;
    private final TextNormalizer normalizer;
    private final EmbeddingService embeddingService;
    private final ThemeMapService themeMapService;
    private final Map<String, Long> documentFrequencies;
    private final double averageDocumentLength;

    public SearchService(
            PlaceRepository placeRepository,
            TextNormalizer normalizer,
            EmbeddingService embeddingService,
            ThemeMapService themeMapService
    ) {
        this.placeRepository = placeRepository;
        this.normalizer = normalizer;
        this.embeddingService = embeddingService;
        this.themeMapService = themeMapService;
        this.documentFrequencies = buildDocumentFrequencies(placeRepository.findAll());
        this.averageDocumentLength = placeRepository.findAll().stream()
                .mapToInt(IndexedPlace::documentLength)
                .average()
                .orElse(1.0);
    }

    public SearchResponse search(SearchRequest request) {
        validateLocation(request);
        List<IndexedPlace> allPlaces = themeMapService.filterPlacesByTheme(placeRepository.findAll(), request.themeId());
        SearchSourceMeta sourceMeta = toSourceMeta(placeRepository.source());

        List<IndexedPlace> candidates = allPlaces.stream()
                .filter(place -> withinRadius(place, request))
                .toList();

        List<String> queryTokens = normalizer.tokenizeForSearch(request.query());
        double[] queryEmbedding = embeddingService.embed(request.query());

        List<ScoreBundle> bundles = candidates.stream()
                .map(place -> buildBundle(place, request, queryTokens, queryEmbedding))
                .toList();

        Map<String, Integer> keywordRanks = buildRanks(bundles, Comparator.comparingDouble(ScoreBundle::keywordRaw).reversed());
        Map<String, Integer> vectorRanks = buildRanks(bundles, Comparator.comparingDouble(ScoreBundle::vectorRaw).reversed());

        double maxKeyword = bundles.stream().mapToDouble(ScoreBundle::keywordRaw).max().orElse(1.0);
        double maxVector = bundles.stream().mapToDouble(ScoreBundle::vectorRaw).max().orElse(1.0);
        double maxRrf = bundles.stream()
                .mapToDouble(bundle -> reciprocalRank(keywordRanks, bundle.place().id()) + reciprocalRank(vectorRanks, bundle.place().id()))
                .max()
                .orElse(1.0);

        List<ScoredBundle> rankedResults = bundles.stream()
                .map(bundle -> scoreBundle(bundle, request, maxKeyword, maxVector, maxRrf, keywordRanks, vectorRanks))
                .sorted(Comparator.comparingDouble(ScoredBundle::finalScore).reversed())
                .toList();

        List<PlaceResultResponse> results = (request.hasLocation() ? rankedResults : diversifyByDistrict(rankedResults)).stream()
                .limit(request.resolvedTopK())
                .map(bundle -> toResponse(bundle, queryEmbedding))
                .toList();

        return new SearchResponse(
                request.query(),
                request.themeId(),
                request.resolvedMode(),
                results.size(),
                request.resolvedTopK(),
                OffsetDateTime.now(),
                sourceMeta,
                results
        );
    }

    public RecommendationResponse recommend(RecommendationRequest request) {
        validateLocation(request.latitude(), request.longitude());
        validateBounds(request.north(), request.south(), request.east(), request.west());
        SearchSourceMeta sourceMeta = toSourceMeta(placeRepository.source());
        List<IndexedPlace> scopedPlaces = themeMapService.filterPlacesByTheme(
                indexedCandidates(null, request.category(), null, null),
                request.themeId()
        );
        List<IndexedPlace> modeCandidates = filterByMode(scopedPlaces, request.mode());
        boolean modeFallback = modeCandidates.isEmpty() && !scopedPlaces.isEmpty();
        List<IndexedPlace> pool = modeFallback ? scopedPlaces : modeCandidates;
        List<IndexedPlace> boundedCandidates = pool.stream()
                .filter(place -> withinBounds(place, request.north(), request.south(), request.east(), request.west()))
                .filter(place -> withinRadius(place, request.latitude(), request.longitude(), request.resolvedRadiusKm()))
                .sorted(Comparator.comparingDouble(place -> distanceForRecommendation(place, request)))
                .limit(resolvedRecommendationLimit(request.limit()))
                .toList();

        boolean scopeFallback = boundedCandidates.isEmpty();
        List<IndexedPlace> effectiveCandidates = scopeFallback
                ? nearestPlaces(pool, request, Math.min(5, request.resolvedLimit()))
                : boundedCandidates;
        List<IndexedPlace> recentFilteredCandidates = excludeRecentWhenPossible(effectiveCandidates, request.resolvedRecentPlaceIds());
        boolean recentFallback = !request.resolvedRecentPlaceIds().isEmpty()
                && recentFilteredCandidates.size() == effectiveCandidates.size()
                && effectiveCandidates.stream().anyMatch(place -> request.resolvedRecentPlaceIds().contains(place.id()));
        effectiveCandidates = recentFilteredCandidates;
        boolean fallbackUsed = modeFallback || scopeFallback || recentFallback || pool.isEmpty();
        String randomScope = recommendationScope(request, modeFallback, scopeFallback, recentFallback, effectiveCandidates.size());

        if (pool.isEmpty()) {
            RecommendationPlaceResponse unavailablePlace = unavailableRecommendationPlace(
                    request,
                    "현재 캐시 데이터가 비어 있어 추천 결과를 만들 수 없습니다."
            );

            return new RecommendationResponse(
                    OffsetDateTime.now(),
                    sourceMeta,
                    true,
                    "캐시 후보 없음",
                    new RecommendationCardResponse(
                            "nearby-random",
                            "근처 추천 준비중",
                            "현재 후보 데이터가 없어 랜덤 추천은 보류했습니다.",
                            unavailablePlace
                    ),
                    new RecommendationCardResponse(
                            "theme-highlight",
                            "테마 추천 준비중",
                            "현재 후보 데이터가 없어 테마 추천은 보류했습니다.",
                            unavailablePlace
                    ),
                    new DateCourseResponse(
                            "데이터 준비중",
                            "현재 데이터 적재를 기다리고 있어 데이트 코스는 보류했습니다.",
                            List.of(
                                    new DateCourseStopResponse("현재", unavailablePlace),
                                    new DateCourseStopResponse("대안", unavailablePlace),
                                    new DateCourseStopResponse("기다림", unavailablePlace)
                            )
                    )
            );
        }

        RecommendationCardResponse nearbyPick = new RecommendationCardResponse(
                "nearby-random",
                "근처 대표 장소",
                fallbackUsed
                        ? "요청 후보가 적어서 캐시 안의 가까운 후보권으로 확장했습니다."
                        : "요청 조건 안의 후보들 중 한 곳을 랜덤으로 골랐습니다.",
                toRecommendationPlace(
                        pickRandomTop(effectiveCandidates, request, 4, place -> true),
                        request,
                        fallbackUsed
                                ? "요청 범위 후보 부족으로 확장된 캐시 후보권에서 선택했습니다."
                                : "현재 요청 조건 안에서 선택한 후보입니다."
                )
        );

        RecommendationCardResponse mealPick = new RecommendationCardResponse(
                "theme-highlight",
                request.themeId() == null || request.themeId().isBlank() ? "추천 포인트" : "테마 하이라이트",
                "현재 후보권에서 체류 가치와 설명 가능성이 높은 장소를 골랐습니다.",
                toRecommendationPlace(
                        pickRandomTop(effectiveCandidates, request, 4, this::isHighlightPlace),
                        request,
                        "현재 후보권과의 연결 신호가 높고 설명이 풍부해 하이라이트 후보로 선정했습니다."
                )
        );

        return new RecommendationResponse(
                OffsetDateTime.now(),
                sourceMeta,
                fallbackUsed,
                randomScope,
                nearbyPick,
                mealPick,
                buildDateCourse(effectiveCandidates, request)
        );
    }

    public List<PlaceListItemResponse> getPlaces() {
        return placeRepository.findAll().stream()
                .map(place -> toPlaceListItemResponse(place, true))
                .toList();
    }

    public PlacesResponse places() {
        return places(null, null, null, null, null, null, null, null, null, null, null, null, null, null, true);
    }

    public PlacesResponse places(
            Double latitude,
            Double longitude,
            Double radiusKm,
            Integer limit,
            boolean includeTourApi
    ) {
        return places(latitude, longitude, radiusKm, null, null, null, null, null, null, null, null, null, null, limit, includeTourApi);
    }

    public PlacesResponse places(
            Double latitude,
            Double longitude,
            Double radiusKm,
            Double north,
            Double south,
            Double east,
            Double west,
            Double zoom,
            String density,
            String category,
            String mode,
            String source,
            Boolean activeFestival,
            Integer limit,
            boolean includeTourApi
    ) {
        validatePlaceListRequest(latitude, longitude, radiusKm, north, south, east, west, limit);
        SearchSourceMeta sourceMeta = toSourceMeta(placeRepository.source());
        SelectionResult selection = selectPlaces(
                latitude,
                longitude,
                radiusKm,
                north,
                south,
                east,
                west,
                zoom,
                density,
                category,
                mode,
                source,
                activeFestival,
                limit
        );
        List<PlaceListItemResponse> places = selection.places().stream()
                .map(place -> toPlaceListItemResponse(place, includeTourApi))
                .toList();
        return new PlacesResponse(
                sourceMeta,
                OffsetDateTime.now(),
                selection.fallbackUsed(),
                selection.randomScope(),
                places.size(),
                places
        );
    }

    private SelectionResult selectPlaces(
            Double latitude,
            Double longitude,
            Double radiusKm,
            Double north,
            Double south,
            Double east,
            Double west,
            Double zoom,
            String density,
            String category,
            String mode,
            String source,
            Boolean activeFestival,
            Integer limit
    ) {
        int resolvedLimit = resolvedPlacesLimit(limit, zoom, density);
        List<IndexedPlace> candidates = indexedCandidates(null, category, source, activeFestival);
        candidates = filterByMode(candidates, mode);
        List<IndexedPlace> boundedCandidates = candidates.stream()
                .filter(place -> withinBounds(place, north, south, east, west))
                .filter(place -> radiusKm == null || withinRadius(place, latitude, longitude, radiusKm))
                .toList();
        boolean fallbackUsed = boundedCandidates.isEmpty() && !candidates.isEmpty();
        List<IndexedPlace> effectiveCandidates = fallbackUsed ? candidates : boundedCandidates;

        List<IndexedPlace> selected;
        if (latitude == null || longitude == null) {
            selected = effectiveCandidates.stream()
                    .limit(resolvedLimit)
                    .toList();
        } else {
            selected = effectiveCandidates.stream()
                    .map(place -> new PlaceDistance(place, haversineKm(latitude, longitude, place.latitude(), place.longitude())))
                    .sorted(Comparator.comparingDouble(PlaceDistance::distanceKm))
                    .limit(resolvedLimit)
                    .map(PlaceDistance::place)
                    .toList();
        }

        return new SelectionResult(
                selected,
                fallbackUsed,
                placesScope(north, south, east, west, zoom, density, category, mode, fallbackUsed, selected.size())
        );
    }

    private int resolvedPlacesLimit(Integer limit, Double zoom, String density) {
        int requestedLimit = resolvedPlacesLimit(limit);
        if (isLowDensityMapRequest(zoom, density)) {
            return Math.min(requestedLimit, LOW_ZOOM_MARKER_LIMIT);
        }
        return requestedLimit;
    }

    private int resolvedRecommendationLimit(Integer limit) {
        if (limit == null) {
            return MAX_RECOMMENDATION_LIMIT;
        }
        return Math.max(1, Math.min(limit, MAX_RECOMMENDATION_LIMIT));
    }

    private boolean isLowDensityMapRequest(Double zoom, String density) {
        if (zoom != null && zoom <= 10.0) {
            return true;
        }
        String normalizedDensity = normalizeFreeText(density);
        return normalizedDensity.equals("low") || normalizedDensity.equals("summary") || normalizedDensity.equals("cluster");
    }

    private List<IndexedPlace> indexedCandidates(String region, String category, String source, Boolean activeFestival) {
        List<IndexedPlace> indexed = placeRepository.indexedCandidates(region, category, source, activeFestival);
        if (category == null || category.isBlank() || !indexed.isEmpty()) {
            return indexed;
        }
        String normalizedCategory = normalizer.normalize(category);
        return placeRepository.findAll().stream()
                .filter(place -> normalizer.normalize(place.category()).contains(normalizedCategory))
                .toList();
    }

    private List<IndexedPlace> filterByMode(List<IndexedPlace> candidates, String mode) {
        String normalizedMode = normalizeFreeText(mode);
        if (normalizedMode.isBlank()) {
            return candidates;
        }
        return candidates.stream()
                .filter(place -> matchesMode(place, normalizedMode))
                .toList();
    }

    private boolean matchesMode(IndexedPlace place, String normalizedMode) {
        return switch (normalizedMode) {
            case "cafe", "카페" -> isCafePlace(place);
            case "festival", "event", "축제", "행사" -> isFestivalPlace(place);
            case "walk", "walking", "산책" -> hasAnyToken(place, List.of("산책", "공원", "길", "둘레", "거리"));
            case "culture", "문화" -> hasAnyToken(place, List.of("문화", "전시", "미술", "박물관", "공연"));
            case "tour", "place", "spot", "관광", "관광지" -> hasAnyToken(place, List.of("관광", "명소", "유적", "체험", "자연"));
            default -> hasAnyToken(place, List.of(normalizedMode));
        };
    }

    private boolean hasAnyToken(IndexedPlace place, List<String> tokens) {
        String haystack = normalizer.normalize(String.join(" ",
                place.name(),
                place.category(),
                place.district(),
                place.summary(),
                String.join(" ", place.tags()),
                String.join(" ", place.themeTags())
        ));
        return tokens.stream()
                .map(normalizer::normalize)
                .anyMatch(token -> !token.isBlank() && haystack.contains(token));
    }

    private boolean isFestivalPlace(IndexedPlace place) {
        return hasAnyToken(place, List.of("축제", "행사", "이벤트", "공연", "전시"));
    }

    private boolean withinBounds(IndexedPlace place, Double north, Double south, Double east, Double west) {
        if (north == null || south == null || east == null || west == null) {
            return true;
        }
        return place.latitude() <= north
                && place.latitude() >= south
                && place.longitude() <= east
                && place.longitude() >= west;
    }

    private List<IndexedPlace> excludeRecentWhenPossible(List<IndexedPlace> candidates, List<String> recentPlaceIds) {
        if (recentPlaceIds == null || recentPlaceIds.isEmpty()) {
            return candidates;
        }
        Set<String> recentIds = new HashSet<>(recentPlaceIds);
        List<IndexedPlace> filtered = candidates.stream()
                .filter(place -> !recentIds.contains(place.id()))
                .toList();
        return filtered.isEmpty() ? candidates : filtered;
    }

    private String placesScope(
            Double north,
            Double south,
            Double east,
            Double west,
            Double zoom,
            String density,
            String category,
            String mode,
            boolean fallbackUsed,
            int count
    ) {
        String base = north != null && south != null && east != null && west != null
                ? "현재 지도 안 후보"
                : "캐시 후보";
        if (fallbackUsed) {
            base = "현재 지도 안 후보 부족으로 캐시 후보권 확장";
        }
        if (isLowDensityMapRequest(zoom, density)) {
            base += " · 낮은 줌 마커 제한";
        }
        if (category != null && !category.isBlank()) {
            base += " · category=" + category;
        }
        if (mode != null && !mode.isBlank()) {
            base += " · mode=" + mode;
        }
        return base + " · " + count + "개";
    }

    private String recommendationScope(
            RecommendationRequest request,
            boolean modeFallback,
            boolean scopeFallback,
            boolean recentFallback,
            int count
    ) {
        String base = request.hasBounds()
                ? "현재 지도 안에서 랜덤"
                : request.latitude() != null && request.longitude() != null
                ? "현재 위치 반경 안에서 랜덤"
                : "전국 랜덤";
        if (scopeFallback) {
            base = "현재 후보 부족으로 캐시 후보권 확장";
        }
        if (modeFallback) {
            base += " · mode 후보 부족으로 전체 모드 보정";
        }
        if (recentFallback) {
            base += " · 최근 후보만 남아 반복 허용";
        }
        return base + " · " + count + "개 후보";
    }

    private String normalizeFreeText(String value) {
        return value == null ? "" : value.trim().toLowerCase();
    }

    private int resolvedPlacesLimit(Integer limit) {
        return resolvedPlacesLimit(limit, null, null);
    }

    private int resolvedPlacesLimit(Integer limit, Double zoom, String density) {
        int requested = limit == null ? MAX_PLACES_LIMIT : Math.max(1, limit);
        int capped = Math.min(requested, MAX_PLACES_LIMIT);
        if (isLowDensityMap(zoom, density)) {
            return Math.min(capped, 120);
        }
        return capped;
    }

    private PlaceListItemResponse toPlaceListItemResponse(IndexedPlace place, boolean includeTourApi) {
        return new PlaceListItemResponse(
                place.id(),
                place.name(),
                place.category(),
                place.district(),
                place.address(),
                place.roadAddress(),
                place.summary(),
                place.tags(),
                place.themeTags(),
                place.latitude(),
                place.longitude(),
                place.sourceAttribution(),
                includeTourApi ? toTourApiResponse(place.tourApi()) : null
        );
    }

    private DateCourseResponse buildDateCourse(List<IndexedPlace> candidates, RecommendationRequest request) {
        if (candidates.isEmpty()) {
            RecommendationPlaceResponse fallback = unavailableRecommendationPlace(
                    request,
                    "현재 후보 데이터가 부족해 데이트 코스 조합을 만들지 못했습니다."
            );

            return new DateCourseResponse(
                    "랜덤 데이트 코스",
                    "데이터가 부족해 데이트 코스는 임시로 보류했습니다.",
                    List.of(
                            new DateCourseStopResponse("준비", fallback),
                            new DateCourseStopResponse("재확인", fallback),
                            new DateCourseStopResponse("대기", fallback)
                    )
            );
        }

        Set<String> usedIds = new HashSet<>();

        IndexedPlace start = pickRandomTop(candidates, request, 4, this::isHighlightPlace);
        start = start == null
                ? pickRandomTop(candidates, request, 4, place -> true)
                : start;
        if (start == null) {
            RecommendationPlaceResponse fallback = unavailableRecommendationPlace(
                    request,
                    "현재 조건에서 후보를 찾지 못했습니다."
            );
            return new DateCourseResponse(
                    "랜덤 데이트 코스",
                    "현재 조건에서 후보를 찾지 못해 임시 구성했습니다.",
                    List.of(
                            new DateCourseStopResponse("준비", fallback),
                            new DateCourseStopResponse("보정", fallback),
                            new DateCourseStopResponse("완료", fallback)
                    )
            );
        }
        usedIds.add(start.id());

        IndexedPlace highlight = pickRandomTop(
                candidates,
                request,
                4,
                place -> isDateFinishPlace(place) && !usedIds.contains(place.id())
        );
        if (highlight == null) {
            highlight = start;
        }
        usedIds.add(highlight.id());

        IndexedPlace finish = pickRandomTop(
                candidates,
                request,
                4,
                place -> !usedIds.contains(place.id())
        );

        if (finish == null) {
            finish = pickRandomTop(candidates, request, 4, place -> !usedIds.contains(place.id()));
        }
        if (finish == null) {
            finish = highlight;
        }

        List<DateCourseStopResponse> stops = List.of(
                new DateCourseStopResponse(
                        "시작",
                        toRecommendationPlace(
                                start,
                                request,
                                "테마를 시작하기 좋은 대표 장소라 첫 정거장으로 배치했습니다."
                        )
                ),
                new DateCourseStopResponse(
                        "하이라이트",
                        toRecommendationPlace(
                                highlight,
                                request,
                                "테마 특성이 가장 잘 드러나는 후보라 중간 하이라이트로 배치했습니다."
                        )
                ),
                new DateCourseStopResponse(
                        "마무리",
                        toRecommendationPlace(
                                finish,
                                request,
                                "동선을 마무리하며 함께 보기 좋은 후보라 마지막 정거장으로 배치했습니다."
                        )
                )
        );

        return new DateCourseResponse(
                "테마 탐방 코스",
                "현재 위치에서 이동 부담이 크지 않은 후보를 시작, 하이라이트, 마무리 순서로 조합했습니다.",
                stops
        );
    }

    private RecommendationPlaceResponse unavailableRecommendationPlace(RecommendationRequest request, String reason) {
        double latitude = request.latitude() == null ? 0.0 : request.latitude();
        double longitude = request.longitude() == null ? 0.0 : request.longitude();

        return new RecommendationPlaceResponse(
                "unavailable",
                "데이터 없음",
                "안내",
                "미확정",
                "데이터 적재 대기",
                reason,
                List.of("데이터 없음", "캐시 준비"),
                List.of(),
                latitude,
                longitude,
                "koreaTour",
                null,
                reason,
                null
        );
    }

    private SearchSourceMeta toSourceMeta(PlaceDataLoadResult source) {
        if (source == null) {
            return new SearchSourceMeta(
                    "unknown",
                    "미지정",
                    "no-source",
                    null,
                    0
            );
        }
        return new SearchSourceMeta(
                source.providerId(),
                source.providerName(),
                source.sourceStatus(),
                source.generatedAt(),
                source.count()
        );
    }

    private ScoreBundle buildBundle(
            IndexedPlace place,
            SearchRequest request,
            List<String> queryTokens,
            double[] queryEmbedding
    ) {
        double keywordRaw = keywordScore(place, queryTokens, request.query());
        double vectorRaw = Math.max(0.0, embeddingService.cosineSimilarity(queryEmbedding, place.embedding()));
        double featureRaw = featureScore(place, queryTokens);
        Double distanceKm = request.hasLocation()
                ? haversineKm(request.latitude(), request.longitude(), place.latitude(), place.longitude())
                : null;
        double geoRaw = distanceKm == null ? 0.0 : geoScore(distanceKm, request.resolvedRadiusKm());

        return new ScoreBundle(place, keywordRaw, vectorRaw, featureRaw, geoRaw, distanceKm);
    }

    private List<IndexedPlace> findNearbyCandidates(RecommendationRequest request, List<IndexedPlace> candidates) {
        return candidates.stream()
                .filter(place -> withinRadius(place, request.latitude(), request.longitude(), request.resolvedRadiusKm()))
                .toList();
    }

    private RecommendationPlaceResponse toRecommendationPlace(
            IndexedPlace place,
            RecommendationRequest request,
            String reason
    ) {
        if (place == null) {
            return null;
        }

        Double distanceKm = request.latitude() == null || request.longitude() == null
                ? null
                : haversineKm(request.latitude(), request.longitude(), place.latitude(), place.longitude());

        return new RecommendationPlaceResponse(
                place.id(),
                place.name(),
                place.category(),
                place.district(),
                place.roadAddress(),
                place.summary(),
                place.tags(),
                place.themeTags(),
                place.latitude(),
                place.longitude(),
                place.sourceAttribution(),
                distanceKm == null ? null : round(distanceKm),
                reason,
                toTourApiResponse(place.tourApi())
        );
    }

    private IndexedPlace pickRandomTop(
            List<IndexedPlace> candidates,
            RecommendationRequest request,
            int bandSize,
            java.util.function.Predicate<IndexedPlace> predicate
    ) {
        List<IndexedPlace> filtered = candidates.stream()
                .filter(predicate)
                .sorted(Comparator.comparingDouble(place -> distanceForRecommendation(place, request)))
                .toList();

        if (filtered.isEmpty()) {
            filtered = candidates.stream()
                    .sorted(Comparator.comparingDouble(place -> distanceForRecommendation(place, request)))
                    .toList();
        }

        if (filtered.isEmpty()) {
            return null;
        }

        int bound = Math.min(bandSize, filtered.size());
        return filtered.get(ThreadLocalRandom.current().nextInt(bound));
    }

    private List<IndexedPlace> nearestPlaces(
            List<IndexedPlace> candidates,
            RecommendationRequest request,
            int limit
    ) {
        return candidates.stream()
                .sorted(Comparator.comparingDouble(place -> distanceForRecommendation(place, request)))
                .limit(limit)
                .toList();
    }

    private boolean isMealPlace(IndexedPlace place) {
        String category = normalizer.normalize(place.category());
        if (category.contains("브런치") || category.contains("레스토랑")) {
            return true;
        }

        return place.tags().stream()
                .map(normalizer::normalize)
                .anyMatch(tag -> tag.contains("브런치") || tag.contains("베이커리") || tag.contains("주말"));
    }

    private boolean isHighlightPlace(IndexedPlace place) {
        if (!place.themeTags().isEmpty()) {
            return true;
        }

        TourApiSeed tourApi = place.tourApi();
        return tourApi != null
                && tourApi.common() != null
                && tourApi.common().overview() != null
                && !tourApi.common().overview().isBlank();
    }

    private boolean isCafePlace(IndexedPlace place) {
        String category = normalizer.normalize(place.category());
        if (category.contains("카페")) {
            return true;
        }

        return place.tags().stream()
                .map(normalizer::normalize)
                .anyMatch(tag -> tag.contains("노트북") || tag.contains("카공") || tag.contains("분위기"));
    }

    private boolean isDateFinishPlace(IndexedPlace place) {
        List<String> tokens = new ArrayList<>();
        tokens.add(normalizer.normalize(place.category()));
        tokens.addAll(place.tags().stream().map(normalizer::normalize).toList());

        return tokens.stream().anyMatch(token ->
                token.contains("데이트")
                        || token.contains("분위기")
                        || token.contains("뷰")
                        || token.contains("창가")
                        || token.contains("조용")
        );
    }

    private ScoredBundle scoreBundle(
            ScoreBundle bundle,
            SearchRequest request,
            double maxKeyword,
            double maxVector,
            double maxRrf,
            Map<String, Integer> keywordRanks,
            Map<String, Integer> vectorRanks
    ) {
        double keywordScore = normalize(bundle.keywordRaw(), maxKeyword);
        double vectorScore = normalize(bundle.vectorRaw(), maxVector);
        double featureScore = bundle.featureRaw();
        double geoScore = bundle.geoRaw();

        double rrfScore = normalize(
                reciprocalRank(keywordRanks, bundle.place().id()) + reciprocalRank(vectorRanks, bundle.place().id()),
                maxRrf
        );

        double finalScore = switch (request.resolvedMode()) {
            case KEYWORD -> request.hasLocation()
                    ? 0.7 * keywordScore + 0.2 * geoScore + 0.1 * featureScore
                    : 0.85 * keywordScore + 0.15 * featureScore;
            case VECTOR -> request.hasLocation()
                    ? 0.65 * vectorScore + 0.2 * geoScore + 0.15 * featureScore
                    : 0.8 * vectorScore + 0.2 * featureScore;
            case HYBRID -> request.hasLocation()
                    ? 0.6 * rrfScore + 0.25 * geoScore + 0.15 * featureScore
                    : 0.8 * rrfScore + 0.2 * featureScore;
        };

        return new ScoredBundle(
                bundle.place(),
                bundle.distanceKm(),
                round(keywordScore),
                round(vectorScore),
                round(featureScore),
                round(geoScore),
                round(finalScore)
        );
    }

    private PlaceResultResponse toResponse(ScoredBundle bundle, double[] queryEmbedding) {
        String evidence = bestEvidence(bundle.place().evidenceCandidates(), queryEmbedding);

        return new PlaceResultResponse(
                bundle.place().id(),
                bundle.place().name(),
                bundle.place().category(),
                bundle.place().district(),
                bundle.place().address(),
                bundle.place().roadAddress(),
                bundle.place().summary(),
                bundle.place().tags(),
                bundle.place().themeTags(),
                bundle.place().latitude(),
                bundle.place().longitude(),
                bundle.place().sourceAttribution(),
                bundle.distanceKm() == null ? null : round(bundle.distanceKm()),
                evidence,
                bundle.keywordScore(),
                bundle.vectorScore(),
                bundle.featureScore(),
                bundle.geoScore(),
                bundle.finalScore(),
                toTourApiResponse(bundle.place().tourApi())
        );
    }

    private TourApiResponse toTourApiResponse(TourApiSeed tourApi) {
        if (tourApi == null) {
            return null;
        }

        TourCommonResponse common = null;
        if (tourApi.common() != null) {
            common = new TourCommonResponse(
                    tourApi.common().tel(),
                    tourApi.common().homepage(),
                    tourApi.common().overview(),
                    tourApi.common().bookTour(),
                    tourApi.common().infoCenter(),
                    tourApi.common().restDate(),
                    tourApi.common().useTime(),
                    tourApi.common().parking(),
                    tourApi.common().useFee(),
                    tourApi.common().refundPolicy(),
                    tourApi.common().expGuide(),
                    tourApi.common().accomCount(),
                    tourApi.common().chkInTime(),
                    tourApi.common().chkOutTime(),
                    tourApi.common().subFacility(),
                    tourApi.common().parkingFee(),
                    tourApi.common().scale(),
                    tourApi.common().spendTime(),
                    tourApi.common().eventStartDate(),
                    tourApi.common().eventEndDate(),
                    tourApi.common().playTime(),
                    tourApi.common().ageLimit()
            );
        }

        return new TourApiResponse(
                tourApi.contentId(),
                tourApi.contentTypeId(),
                tourApi.contentTypeLabel(),
                common,
                tourApi.intro(),
                tourApi.images() == null ? List.of() : tourApi.images().stream()
                        .map(image -> new TourImageResponse(
                                image.originImgUrl(),
                                image.smallImageUrl(),
                                image.imgName(),
                                image.serialNum()
                        ))
                        .toList(),
                tourApi.pet() == null ? null : new TourPetResponse(
                        tourApi.pet().petTursmInfo(),
                        tourApi.pet().acmpyTypeCd(),
                        tourApi.pet().relaPosesFclty(),
                        tourApi.pet().relaFrnshPrdlst(),
                        tourApi.pet().etcAcmpyInfo(),
                        tourApi.pet().relaPurcPrdlst(),
                        tourApi.pet().acmpyPsblCpam()
                )
        );
    }

    private double keywordScore(IndexedPlace place, List<String> queryTokens, String rawQuery) {
        if (queryTokens.isEmpty()) {
            return 0.0;
        }

        double score = 0.0;
        for (String token : queryTokens) {
            int termFrequency = place.termFrequencies().getOrDefault(token, 0);
            if (termFrequency == 0) {
                continue;
            }

            double inverseDocumentFrequency = inverseDocumentFrequency(token);
            double denominator = termFrequency + BM25_K1 * (1 - BM25_B + BM25_B * (place.documentLength() / averageDocumentLength));
            score += inverseDocumentFrequency * ((termFrequency * (BM25_K1 + 1)) / denominator);
        }

        String normalizedQuery = normalizer.normalize(rawQuery);
        String normalizedName = normalizer.normalize(place.name());
        if (!normalizedQuery.isBlank() && normalizedName.contains(normalizedQuery)) {
            score += 1.1;
        }

        return score;
    }

    private double inverseDocumentFrequency(String token) {
        long totalDocuments = placeRepository.findAll().size();
        long documentFrequency = documentFrequencies.getOrDefault(token, 0L);
        return Math.log1p((totalDocuments - documentFrequency + 0.5) / (documentFrequency + 0.5));
    }

    private double featureScore(IndexedPlace place, List<String> queryTokens) {
        if (queryTokens.isEmpty()) {
            return 0.0;
        }

        Set<String> featureTokens = place.featureTokens();
        long matches = queryTokens.stream()
                .filter(featureTokens::contains)
                .distinct()
                .count();

        return Math.min(1.0, matches / (double) Math.min(queryTokens.size(), 6));
    }

    private String bestEvidence(List<IndexedEvidence> evidences, double[] queryEmbedding) {
        Map<String, double[]> resolvedEmbeddings = embeddingService.embedAll(evidences.stream()
                .map(IndexedEvidence::text)
                .toList());

        return evidences.stream()
                .max(Comparator.comparingDouble(evidence -> embeddingService.cosineSimilarity(
                        queryEmbedding,
                        evidence.embedding() == null
                                ? resolvedEmbeddings.get(evidence.text())
                                : evidence.embedding()
                )))
                .map(IndexedEvidence::text)
                .orElse("");
    }

    private boolean withinRadius(IndexedPlace place, SearchRequest request) {
        if (!request.hasLocation()) {
            return true;
        }
        double distanceKm = haversineKm(request.latitude(), request.longitude(), place.latitude(), place.longitude());
        return distanceKm <= request.resolvedRadiusKm();
    }

    private boolean withinRadius(IndexedPlace place, Double latitude, Double longitude, double radiusKm) {
        if (latitude == null || longitude == null) {
            return true;
        }
        return haversineKm(latitude, longitude, place.latitude(), place.longitude()) <= radiusKm;
    }

    private double geoScore(double distanceKm, double radiusKm) {
        double safeRadius = Math.max(0.1, radiusKm);
        return Math.max(0.0, 1.0 - (distanceKm / safeRadius));
    }

    private double haversineKm(double lat1, double lon1, double lat2, double lon2) {
        double earthRadiusKm = 6371.0;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double originLat = Math.toRadians(lat1);
        double targetLat = Math.toRadians(lat2);

        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(originLat) * Math.cos(targetLat) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return earthRadiusKm * c;
    }

    private Map<String, Long> buildDocumentFrequencies(List<IndexedPlace> places) {
        Map<String, Long> frequencies = new HashMap<>();
        for (IndexedPlace place : places) {
            place.termFrequencies().keySet().forEach(token -> frequencies.merge(token, 1L, Long::sum));
        }
        return Map.copyOf(frequencies);
    }

    private Map<String, Integer> buildRanks(List<ScoreBundle> bundles, Comparator<ScoreBundle> comparator) {
        List<ScoreBundle> sorted = bundles.stream()
                .sorted(comparator)
                .toList();

        Map<String, Integer> ranks = new LinkedHashMap<>();
        int rank = 1;
        for (ScoreBundle bundle : sorted) {
            ranks.put(bundle.place().id(), rank++);
        }
        return ranks;
    }

    private double reciprocalRank(Map<String, Integer> ranks, String placeId) {
        return 1.0 / (RRF_CONSTANT + ranks.getOrDefault(placeId, 999));
    }

    private List<ScoredBundle> diversifyByDistrict(List<ScoredBundle> rankedResults) {
        Map<String, List<ScoredBundle>> grouped = new LinkedHashMap<>();
        for (ScoredBundle result : rankedResults) {
            grouped.computeIfAbsent(result.place().district(), ignored -> new ArrayList<>()).add(result);
        }

        List<ScoredBundle> diversified = new ArrayList<>();
        int cursor = 0;
        while (diversified.size() < rankedResults.size()) {
            boolean added = false;
            for (List<ScoredBundle> group : grouped.values()) {
                if (cursor < group.size()) {
                    diversified.add(group.get(cursor));
                    added = true;
                }
            }
            if (!added) {
                break;
            }
            cursor++;
        }
        return diversified;
    }

    private double normalize(double score, double maxScore) {
        if (maxScore <= 0.0) {
            return 0.0;
        }
        return Math.max(0.0, Math.min(1.0, score / maxScore));
    }

    private double round(double value) {
        return Math.round(value * 1000.0) / 1000.0;
    }

    private void validateLocation(SearchRequest request) {
        validateLocation(request.latitude(), request.longitude());
    }

    private void validateLocation(Double latitude, Double longitude) {
        boolean hasLatitude = latitude != null;
        boolean hasLongitude = longitude != null;

        if (hasLatitude != hasLongitude) {
            throw new ResponseStatusException(BAD_REQUEST, "latitude와 longitude는 함께 전달되어야 합니다.");
        }
    }

    private void validatePlaceListRequest(
            Double latitude,
            Double longitude,
            Double radiusKm,
            Double north,
            Double south,
            Double east,
            Double west,
            Integer limit
    ) {
        validateLocation(latitude, longitude);
        validateBounds(north, south, east, west);
        if (radiusKm != null && radiusKm <= 0.0) {
            throw new ResponseStatusException(BAD_REQUEST, "radiusKm는 양수여야 합니다.");
        }
        if (limit != null && limit < 1) {
            throw new ResponseStatusException(BAD_REQUEST, "limit는 1 이상이어야 합니다.");
        }
    }

    private void validatePlaceListRequest(Double latitude, Double longitude, Double radiusKm, Integer limit) {
        validateLocation(latitude, longitude);
        if (radiusKm != null && radiusKm <= 0.0) {
            throw new ResponseStatusException(BAD_REQUEST, "radiusKm는 양수여야 합니다.");
        }
        if (limit != null && limit < 1) {
            throw new ResponseStatusException(BAD_REQUEST, "limit는 1 이상이어야 합니다.");
        }
    }

    private void validateBounds(Double north, Double south, Double east, Double west) {
        long count = List.of(north, south, east, west).stream().filter(value -> value != null).count();
        if (count > 0 && count < 4) {
            throw new ResponseStatusException(BAD_REQUEST, "north/south/east/west는 함께 전달되어야 합니다.");
        }
        if (count == 4 && (south > north || west > east)) {
            throw new ResponseStatusException(BAD_REQUEST, "지도 bounds 값이 올바르지 않습니다.");
        }
    }

    private double distanceForRecommendation(IndexedPlace place, RecommendationRequest request) {
        if (request.latitude() == null || request.longitude() == null) {
            return 0.0;
        }
        return haversineKm(request.latitude(), request.longitude(), place.latitude(), place.longitude());
    }

    private record ScoreBundle(
            IndexedPlace place,
            double keywordRaw,
            double vectorRaw,
            double featureRaw,
            double geoRaw,
            Double distanceKm
    ) {
    }

    private record ScoredBundle(
            IndexedPlace place,
            Double distanceKm,
            double keywordScore,
            double vectorScore,
            double featureScore,
            double geoScore,
            double finalScore
    ) {
    }

    private record PlaceDistance(
            IndexedPlace place,
            double distanceKm
    ) {
    }

    private record SelectionResult(
            List<IndexedPlace> places,
            boolean fallbackUsed,
            String randomScope
    ) {
    }
}

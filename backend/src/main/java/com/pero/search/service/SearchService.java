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
        List<IndexedPlace> allPlaces = themeMapService.filterPlacesByTheme(placeRepository.findAll(), request.themeId());

        if (allPlaces.isEmpty()) {
            RecommendationPlaceResponse unavailablePlace = unavailableRecommendationPlace(
                    request,
                    "현재 캐시 데이터가 비어 있어 추천 결과를 만들 수 없습니다."
            );

            return new RecommendationResponse(
                    OffsetDateTime.now(),
                    true,
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

        List<IndexedPlace> nearbyCandidates = findNearbyCandidates(request, allPlaces);
        boolean fallbackUsed = nearbyCandidates.isEmpty();
        List<IndexedPlace> effectiveCandidates = fallbackUsed
                ? nearestPlaces(allPlaces, request, 5)
                : nearbyCandidates;

        RecommendationCardResponse nearbyPick = new RecommendationCardResponse(
                "nearby-random",
                "근처 대표 장소",
                fallbackUsed
                        ? "반경 안 후보가 적어서 가장 가까운 장소권에서 골랐습니다."
                        : "현재 반경 안에서 가까운 후보들 중 한 곳을 랜덤으로 골랐습니다.",
                toRecommendationPlace(
                        pickRandomTop(effectiveCandidates, request, 4, place -> true),
                        request,
                        fallbackUsed
                                ? "반경 밖까지 넓혀 가장 가까운 후보권에서 선택했습니다."
                                : "현재 위치에서 무리 없이 들를 수 있는 후보 중 하나입니다."
                )
        );

        RecommendationCardResponse mealPick = new RecommendationCardResponse(
                "theme-highlight",
                request.themeId() == null || request.themeId().isBlank() ? "추천 포인트" : "테마 하이라이트",
                "현재 테마 안에서 체류 가치와 설명 가능성이 높은 장소를 골랐습니다.",
                toRecommendationPlace(
                        pickRandomTop(effectiveCandidates, request, 4, this::isHighlightPlace),
                        request,
                        "현재 테마와의 연결 신호가 높고 상세 설명이 풍부해 하이라이트 후보로 선정했습니다."
                )
        );

        return new RecommendationResponse(
                OffsetDateTime.now(),
                toSourceMeta(placeRepository.source()),
                fallbackUsed,
                fallbackUsed ? "요청 반경 후보 부족으로 가까운 후보권까지 확장" : "요청 범위 안에서 랜덤",
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
        validatePlaceListRequest(latitude, longitude, radiusKm, limit);
        validateBounds(north, south, east, west);
        SearchSourceMeta sourceMeta = toSourceMeta(placeRepository.source());
        List<IndexedPlace> indexedPlaces = selectPlaces(
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
        List<PlaceListItemResponse> places = indexedPlaces.stream()
                .map(place -> toPlaceListItemResponse(place, includeTourApi))
                .toList();
        return new PlacesResponse(sourceMeta, OffsetDateTime.now(), false, placesRandomScope(north, south, east, west, zoom, category, mode), places.size(), places);
    }

    private List<IndexedPlace> selectPlaces(
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
        return placeRepository.findAll().stream()
                .filter(place -> withinBounds(place, north, south, east, west))
                .filter(place -> radiusKm == null || withinRadius(place, latitude, longitude, radiusKm))
                .filter(place -> matchesTextFilter(place.category(), category))
                .filter(place -> matchesRandomMode(place, mode))
                .filter(place -> matchesTextFilter(place.sourceAttribution(), source))
                .filter(place -> matchesActiveFestival(place, activeFestival))
                .map(place -> new PlaceDistance(place, latitude == null || longitude == null ? 0.0 : haversineKm(latitude, longitude, place.latitude(), place.longitude())))
                .sorted(Comparator.comparingDouble(PlaceDistance::distanceKm))
                .limit(resolvedLimit)
                .map(PlaceDistance::place)
                .toList();
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
        boolean any = north != null || south != null || east != null || west != null;
        boolean all = north != null && south != null && east != null && west != null;
        if (any && !all) {
            throw new ResponseStatusException(BAD_REQUEST, "지도 bounds는 north/south/east/west를 함께 보내야 합니다.");
        }
        if (all && north < south) {
            throw new ResponseStatusException(BAD_REQUEST, "north는 south 이상이어야 합니다.");
        }
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

    private boolean matchesTextFilter(String value, String requested) {
        if (requested == null || requested.isBlank()) {
            return true;
        }
        String normalizedValue = normalizer.normalize(value);
        String normalizedRequest = normalizer.normalize(requested);
        return normalizedValue.contains(normalizedRequest) || normalizedRequest.contains(normalizedValue);
    }

    private boolean matchesRandomMode(IndexedPlace place, String mode) {
        if (mode == null || mode.isBlank()) {
            return true;
        }
        String normalizedMode = normalizer.normalize(mode);
        if (normalizedMode.contains("카페")) {
            return isCafePlace(place);
        }
        if (normalizedMode.contains("축제") || normalizedMode.contains("행사")) {
            return matchesAnyPlaceToken(place, "축제", "행사", "공연");
        }
        if (normalizedMode.contains("산책") || normalizedMode.contains("공원")) {
            return matchesAnyPlaceToken(place, "산책", "공원", "자연");
        }
        if (normalizedMode.contains("문화")) {
            return matchesAnyPlaceToken(place, "문화", "전시", "공연", "미술", "박물관");
        }
        if (normalizedMode.contains("관광") || normalizedMode.contains("장소")) {
            return true;
        }
        return matchesAnyPlaceToken(place, normalizedMode);
    }

    private boolean matchesAnyPlaceToken(IndexedPlace place, String... tokens) {
        List<String> values = new ArrayList<>();
        values.add(place.category());
        values.add(place.name());
        values.add(place.summary());
        values.addAll(place.tags());
        values.addAll(place.themeTags());
        String haystack = normalizer.normalize(String.join(" ", values));
        for (String token : tokens) {
            if (haystack.contains(normalizer.normalize(token))) {
                return true;
            }
        }
        return false;
    }

    private boolean matchesActiveFestival(IndexedPlace place, Boolean activeFestival) {
        if (activeFestival == null || !activeFestival) {
            return true;
        }
        return matchesAnyPlaceToken(place, "축제", "행사", "공연");
    }

    private boolean isLowDensityMap(Double zoom, String density) {
        if (density != null && (density.equalsIgnoreCase("low") || density.equalsIgnoreCase("summary") || density.equalsIgnoreCase("cluster"))) {
            return true;
        }
        return zoom != null && zoom < 12.0;
    }

    private String placesRandomScope(Double north, Double south, Double east, Double west, Double zoom, String category, String mode) {
        List<String> parts = new ArrayList<>();
        if (north != null && south != null && east != null && west != null) {
            parts.add("현재 지도 안");
        }
        if (mode != null && !mode.isBlank()) {
            parts.add(mode + " 후보");
        } else if (category != null && !category.isBlank()) {
            parts.add(category + " 후보");
        } else {
            parts.add("지도 후보");
        }
        if (zoom != null && zoom < 12.0) {
            parts.add("낮은 줌 marker 제한");
        }
        return String.join(" · ", parts);
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
}

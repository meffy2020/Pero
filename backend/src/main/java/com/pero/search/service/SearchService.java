package com.pero.search.service;

import com.pero.search.dto.DateCourseResponse;
import com.pero.search.dto.DateCourseStopResponse;
import com.pero.search.dto.PlaceResultResponse;
import com.pero.search.dto.RecommendationCardResponse;
import com.pero.search.dto.RecommendationPlaceResponse;
import com.pero.search.dto.RecommendationRequest;
import com.pero.search.dto.RecommendationResponse;
import com.pero.search.dto.SearchRequest;
import com.pero.search.dto.SearchResponse;
import com.pero.search.model.IndexedPlace;
import com.pero.search.model.IndexedEvidence;
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

    private final PlaceRepository placeRepository;
    private final TextNormalizer normalizer;
    private final EmbeddingService embeddingService;
    private final Map<String, Long> documentFrequencies;
    private final double averageDocumentLength;

    public SearchService(
            PlaceRepository placeRepository,
            TextNormalizer normalizer,
            EmbeddingService embeddingService
    ) {
        this.placeRepository = placeRepository;
        this.normalizer = normalizer;
        this.embeddingService = embeddingService;
        this.documentFrequencies = buildDocumentFrequencies(placeRepository.findAll());
        this.averageDocumentLength = placeRepository.findAll().stream()
                .mapToInt(IndexedPlace::documentLength)
                .average()
                .orElse(1.0);
    }

    public SearchResponse search(SearchRequest request) {
        validateLocation(request);

        List<IndexedPlace> candidates = placeRepository.findAll().stream()
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

        List<PlaceResultResponse> results = bundles.stream()
                .map(bundle -> toResponse(bundle, request, maxKeyword, maxVector, maxRrf, keywordRanks, vectorRanks))
                .sorted(Comparator.comparingDouble(PlaceResultResponse::finalScore).reversed())
                .limit(request.resolvedTopK())
                .toList();

        return new SearchResponse(
                request.query(),
                request.resolvedMode(),
                results.size(),
                request.resolvedTopK(),
                OffsetDateTime.now(),
                results
        );
    }

    public RecommendationResponse recommend(RecommendationRequest request) {
        validateLocation(request.latitude(), request.longitude());

        List<IndexedPlace> nearbyCandidates = findNearbyCandidates(request);
        boolean fallbackUsed = nearbyCandidates.isEmpty();
        List<IndexedPlace> effectiveCandidates = fallbackUsed
                ? nearestPlaces(placeRepository.findAll(), request, 5)
                : nearbyCandidates;

        RecommendationCardResponse nearbyPick = new RecommendationCardResponse(
                "nearby-random",
                "랜덤 장소",
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
                "meal-nearby",
                "근처 식사 추천",
                "브런치, 레스토랑, 베이커리 성격의 후보를 추려 랜덤으로 골랐습니다.",
                toRecommendationPlace(
                        pickRandomTop(effectiveCandidates, request, 4, this::isMealPlace),
                        request,
                        "식사 시작이나 가벼운 브런치에 맞는 장소 유형이라 식사 후보로 선정했습니다."
                )
        );

        return new RecommendationResponse(
                OffsetDateTime.now(),
                fallbackUsed,
                nearbyPick,
                mealPick,
                buildDateCourse(effectiveCandidates, request)
        );
    }

    public List<Map<String, Object>> getPlaces() {
        return placeRepository.findAll().stream()
                .map(place -> Map.<String, Object>of(
                        "id", place.id(),
                        "name", place.name(),
                        "category", place.category(),
                        "district", place.district(),
                        "latitude", place.latitude(),
                        "longitude", place.longitude(),
                        "tags", place.tags()
                ))
                .toList();
    }

    private DateCourseResponse buildDateCourse(List<IndexedPlace> candidates, RecommendationRequest request) {
        Set<String> usedIds = new HashSet<>();

        IndexedPlace meal = pickRandomTop(candidates, request, 4, this::isMealPlace);
        usedIds.add(meal.id());

        IndexedPlace cafe = pickRandomTop(
                candidates,
                request,
                4,
                place -> isCafePlace(place) && !usedIds.contains(place.id())
        );
        usedIds.add(cafe.id());

        IndexedPlace finish = pickRandomTop(
                candidates,
                request,
                4,
                place -> isDateFinishPlace(place) && !usedIds.contains(place.id())
        );

        if (finish == null) {
            finish = pickRandomTop(candidates, request, 4, place -> !usedIds.contains(place.id()));
        }
        if (finish == null) {
            finish = cafe;
        }

        List<DateCourseStopResponse> stops = List.of(
                new DateCourseStopResponse(
                        "식사",
                        toRecommendationPlace(
                                meal,
                                request,
                                "식사나 브런치로 시작하기 좋은 유형이라 첫 코스로 배치했습니다."
                        )
                ),
                new DateCourseStopResponse(
                        "카페",
                        toRecommendationPlace(
                                cafe,
                                request,
                                "대화하거나 머무르기 좋은 카페 성격이라 중간 코스로 배치했습니다."
                        )
                ),
                new DateCourseStopResponse(
                        "마무리",
                        toRecommendationPlace(
                                finish,
                                request,
                                "분위기, 뷰, 조용한 체류 특성을 기준으로 마무리 코스로 골랐습니다."
                        )
                )
        );

        return new DateCourseResponse(
                "랜덤 데이트 코스",
                "현재 위치에서 이동 부담이 크지 않은 후보를 식사, 카페, 마무리 순서로 조합했습니다.",
                stops
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
        String evidence = bestEvidence(place.evidenceCandidates(), queryEmbedding);

        return new ScoreBundle(place, keywordRaw, vectorRaw, featureRaw, geoRaw, distanceKm, evidence);
    }

    private List<IndexedPlace> findNearbyCandidates(RecommendationRequest request) {
        return placeRepository.findAll().stream()
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
                place.latitude(),
                place.longitude(),
                distanceKm == null ? null : round(distanceKm),
                reason
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

    private PlaceResultResponse toResponse(
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

        return new PlaceResultResponse(
                bundle.place().id(),
                bundle.place().name(),
                bundle.place().category(),
                bundle.place().district(),
                bundle.place().address(),
                bundle.place().roadAddress(),
                bundle.place().summary(),
                bundle.place().tags(),
                bundle.place().latitude(),
                bundle.place().longitude(),
                bundle.distanceKm() == null ? null : round(bundle.distanceKm()),
                bundle.evidence(),
                round(keywordScore),
                round(vectorScore),
                round(featureScore),
                round(geoScore),
                round(finalScore)
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
        return evidences.stream()
                .max(Comparator.comparingDouble(evidence -> embeddingService.cosineSimilarity(queryEmbedding, evidence.embedding())))
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
            Double distanceKm,
            String evidence
    ) {
    }
}

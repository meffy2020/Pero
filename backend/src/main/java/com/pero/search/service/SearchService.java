package com.pero.search.service;

import com.pero.search.dto.PlaceResultResponse;
import com.pero.search.dto.SearchRequest;
import com.pero.search.dto.SearchResponse;
import com.pero.search.model.IndexedPlace;
import com.pero.search.model.IndexedReview;
import com.pero.search.repository.PlaceRepository;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

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
        String evidence = bestEvidence(place.reviews(), queryEmbedding);

        return new ScoreBundle(place, keywordRaw, vectorRaw, featureRaw, geoRaw, distanceKm, evidence);
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

    private String bestEvidence(List<IndexedReview> reviews, double[] queryEmbedding) {
        return reviews.stream()
                .max(Comparator.comparingDouble(review -> embeddingService.cosineSimilarity(queryEmbedding, review.embedding())))
                .map(IndexedReview::sentence)
                .orElse("");
    }

    private boolean withinRadius(IndexedPlace place, SearchRequest request) {
        if (!request.hasLocation()) {
            return true;
        }
        double distanceKm = haversineKm(request.latitude(), request.longitude(), place.latitude(), place.longitude());
        return distanceKm <= request.resolvedRadiusKm();
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
        boolean hasLatitude = request.latitude() != null;
        boolean hasLongitude = request.longitude() != null;

        if (hasLatitude != hasLongitude) {
            throw new ResponseStatusException(BAD_REQUEST, "latitude와 longitude는 함께 전달되어야 합니다.");
        }
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

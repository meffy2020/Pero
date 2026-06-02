package com.pero.search.repository;

import com.pero.search.data.PlaceDataLoadResult;
import com.pero.search.data.PlaceDataProviderRegistry;
import com.pero.search.model.IndexedEvidence;
import com.pero.search.model.IndexedPlace;
import com.pero.search.model.PlaceSeed;
import com.pero.search.service.EmbeddingService;
import com.pero.search.service.ThemeMetadataSupport;
import com.pero.search.service.TextNormalizer;
import org.springframework.stereotype.Repository;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Repository
public class PlaceRepository {

    private final PlaceDataLoadResult dataSource;
    private final List<IndexedPlace> places;

    public PlaceRepository(
            PlaceDataProviderRegistry providerRegistry,
            TextNormalizer normalizer,
            EmbeddingService embeddingService
    ) {
        this.dataSource = providerRegistry.loadActiveData();
        List<PlaceSeed> seeds = dataSource.places();
        this.places = loadPlaces(normalizer, embeddingService, seeds, dataSource.providerId());
    }

    public List<IndexedPlace> findAll() {
        return places;
    }

    public PlaceDataLoadResult source() {
        return dataSource;
    }

    private List<IndexedPlace> loadPlaces(
            TextNormalizer normalizer,
            EmbeddingService embeddingService,
            List<PlaceSeed> seeds,
            String defaultSourceAttribution
    ) {
        if (seeds == null || seeds.isEmpty()) {
            return List.of();
        }

        List<PreparedPlace> preparedPlaces = new ArrayList<>();
        Set<String> searchableTexts = new LinkedHashSet<>();
        for (PlaceSeed seed : seeds) {
            List<String> tags = seed.tags() == null ? List.of() : List.copyOf(seed.tags());
            List<String> themeTags = seed.themeTags() == null || seed.themeTags().isEmpty()
                    ? ThemeMetadataSupport.deriveThemeTags(
                    seed.name(),
                    seed.category(),
                    seed.district(),
                    seed.summary(),
                    tags,
                    seed.searchHints(),
                    seed.tourApi()
            )
                    : List.copyOf(seed.themeTags());
            List<String> searchHints = seed.searchHints() == null ? List.of() : List.copyOf(seed.searchHints());
            String sourceAttribution = seed.sourceAttribution() == null || seed.sourceAttribution().isBlank()
                    ? defaultSourceAttribution
                    : seed.sourceAttribution();

            String searchableText = String.join(
                    " ",
                    seed.name(),
                    seed.category(),
                    seed.district(),
                    seed.address(),
                    seed.roadAddress(),
                    seed.summary(),
                    String.join(" ", tags),
                    String.join(" ", themeTags),
                    String.join(" ", searchHints)
            );

            List<String> searchableTokens = normalizer.tokenizeForSearch(searchableText);
            Map<String, Integer> termFrequencies = new LinkedHashMap<>();
            for (String token : searchableTokens) {
                termFrequencies.merge(token, 1, Integer::sum);
            }

            Set<String> featureTokens = new LinkedHashSet<>(normalizer.tokenizeForSearch(seed.summary()));
            tags.forEach(tag -> featureTokens.addAll(normalizer.tokenizeForSearch(tag)));
            featureTokens.addAll(normalizer.tokenizeForSearch(seed.category()));
            searchHints.forEach(hint -> featureTokens.addAll(normalizer.tokenizeForSearch(hint)));

            List<String> evidenceTexts = buildEvidenceCandidateTexts(seed, tags, searchHints);
            preparedPlaces.add(new PreparedPlace(
                    seed.id(),
                    seed.name(),
                    seed.category(),
                    seed.district(),
                    seed.address(),
                    seed.roadAddress(),
                    seed.latitude(),
                    seed.longitude(),
                    seed.summary(),
                    tags,
                    themeTags,
                    sourceAttribution,
                    Collections.unmodifiableMap(termFrequencies),
                    Collections.unmodifiableSet(featureTokens),
                    searchableTokens.size(),
                    searchableText,
                    evidenceTexts,
                    seed.tourApi()
            ));
            searchableTexts.add(searchableText);
        }

        Map<String, double[]> searchableEmbeddings = embeddingService.embedAll(List.copyOf(searchableTexts));
        List<IndexedPlace> indexedPlaces = new ArrayList<>();
        for (PreparedPlace preparedPlace : preparedPlaces) {
            List<IndexedEvidence> evidenceCandidates = preparedPlace.evidenceTexts().stream()
                    .map(text -> new IndexedEvidence(text, null))
                    .toList();

            indexedPlaces.add(new IndexedPlace(
                    preparedPlace.id(),
                    preparedPlace.name(),
                    preparedPlace.category(),
                    preparedPlace.district(),
                    preparedPlace.address(),
                    preparedPlace.roadAddress(),
                    preparedPlace.latitude(),
                    preparedPlace.longitude(),
                    preparedPlace.summary(),
                    preparedPlace.tags(),
                    preparedPlace.themeTags(),
                    preparedPlace.sourceAttribution(),
                    evidenceCandidates,
                    preparedPlace.termFrequencies(),
                    preparedPlace.featureTokens(),
                    preparedPlace.documentLength(),
                    searchableEmbeddings.getOrDefault(preparedPlace.searchableText(), embeddingService.embed(preparedPlace.searchableText())),
                    preparedPlace.tourApi()
            ));
        }
        return List.copyOf(indexedPlaces);
    }

    private List<String> buildEvidenceCandidateTexts(
            PlaceSeed seed,
            List<String> tags,
            List<String> searchHints
    ) {
        List<String> candidates = new ArrayList<>();
        candidates.add(seed.summary());
        candidates.add(seed.category() + " · " + seed.district());
        if (seed.tourApi() != null && seed.tourApi().common() != null) {
            if (seed.tourApi().common().overview() != null && !seed.tourApi().common().overview().isBlank()) {
                candidates.add(seed.tourApi().common().overview());
            }
            if (seed.tourApi().common().useTime() != null && !seed.tourApi().common().useTime().isBlank()) {
                candidates.add(seed.tourApi().common().useTime());
            }
        }
        tags.stream()
                .limit(4)
                .map(tag -> tag + " 관련 특징이 있는 장소")
                .forEach(candidates::add);
        candidates.addAll(searchHints);

        return candidates.stream()
                .filter(candidate -> candidate != null && !candidate.isBlank())
                .distinct()
                .toList();
    }

    private record PreparedPlace(
            String id,
            String name,
            String category,
            String district,
            String address,
            String roadAddress,
            double latitude,
            double longitude,
            String summary,
            List<String> tags,
            List<String> themeTags,
            String sourceAttribution,
            Map<String, Integer> termFrequencies,
            Set<String> featureTokens,
            int documentLength,
            String searchableText,
            List<String> evidenceTexts,
            com.pero.search.model.TourApiSeed tourApi
    ) {
    }
}

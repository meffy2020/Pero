package com.pero.search.repository;

import com.pero.search.data.PlaceDataLoadResult;
import com.pero.search.data.PlaceDataProviderRegistry;
import com.pero.search.model.IndexedEvidence;
import com.pero.search.model.IndexedPlace;
import com.pero.search.model.PlaceSeed;
import com.pero.search.service.EmbeddingService;
import com.pero.search.service.TextNormalizer;
import org.springframework.stereotype.Repository;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
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
        this.places = loadPlaces(normalizer, embeddingService, seeds);
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
            List<PlaceSeed> seeds
    ) {
        if (seeds == null || seeds.isEmpty()) {
            return List.of();
        }

        List<IndexedPlace> indexedPlaces = new ArrayList<>();
        for (PlaceSeed seed : seeds) {
            List<String> tags = seed.tags() == null ? List.of() : List.copyOf(seed.tags());
            List<String> searchHints = seed.searchHints() == null ? List.of() : List.copyOf(seed.searchHints());

            String searchableText = String.join(
                    " ",
                    seed.name(),
                    seed.category(),
                    seed.district(),
                    seed.address(),
                    seed.roadAddress(),
                    seed.summary(),
                    String.join(" ", tags),
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

            List<IndexedEvidence> evidenceCandidates = buildEvidenceCandidates(seed, tags, searchHints, embeddingService);

            indexedPlaces.add(new IndexedPlace(
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
                    evidenceCandidates,
                    Collections.unmodifiableMap(termFrequencies),
                    Collections.unmodifiableSet(featureTokens),
                    searchableTokens.size(),
                    embeddingService.embed(searchableText)
            ));
        }
        return List.copyOf(indexedPlaces);
    }

    private List<IndexedEvidence> buildEvidenceCandidates(
            PlaceSeed seed,
            List<String> tags,
            List<String> searchHints,
            EmbeddingService embeddingService
    ) {
        List<String> candidates = new ArrayList<>();
        candidates.add(seed.summary());
        candidates.add(seed.category() + " · " + seed.district());
        tags.stream()
                .limit(4)
                .map(tag -> tag + " 관련 특징이 있는 장소")
                .forEach(candidates::add);
        candidates.addAll(searchHints);

        return candidates.stream()
                .filter(candidate -> candidate != null && !candidate.isBlank())
                .distinct()
                .map(text -> new IndexedEvidence(text, embeddingService.embed(text)))
                .toList();
    }
}


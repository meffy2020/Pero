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

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
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
    private static final DateTimeFormatter TOUR_DATE_FORMAT = DateTimeFormatter.BASIC_ISO_DATE;

    private final List<IndexedPlace> places;
    private final Map<String, List<IndexedPlace>> placesByRegion;
    private final Map<String, List<IndexedPlace>> placesByCategory;
    private final Map<String, List<IndexedPlace>> placesBySource;
    private final Map<Boolean, List<IndexedPlace>> placesByActiveFestival;

    public PlaceRepository(
            PlaceDataProviderRegistry providerRegistry,
            TextNormalizer normalizer,
            EmbeddingService embeddingService
    ) {
        this.dataSource = providerRegistry.loadActiveData();
        List<PlaceSeed> seeds = dataSource.places();
        this.places = loadPlaces(normalizer, embeddingService, seeds, dataSource.providerId());
        this.placesByRegion = buildIndex(this.places, place -> normalizeIndexKey(place.district()));
        this.placesByCategory = buildIndex(this.places, place -> normalizeIndexKey(place.category()));
        this.placesBySource = buildIndex(this.places, place -> normalizeIndexKey(place.sourceAttribution()));
        this.placesByActiveFestival = buildActiveFestivalIndex(this.places);
    }

    public List<IndexedPlace> findAll() {
        return places;
    }

    public PlaceDataLoadResult source() {
        return dataSource;
    }

    public List<IndexedPlace> findByRegion(String region) {
        return findFromIndex(placesByRegion, region);
    }

    public List<IndexedPlace> findByCategory(String category) {
        return findFromIndex(placesByCategory, category);
    }

    public List<IndexedPlace> findBySource(String source) {
        return findFromIndex(placesBySource, source);
    }

    public List<IndexedPlace> findByActiveFestival(boolean activeFestival) {
        return placesByActiveFestival.getOrDefault(activeFestival, List.of());
    }

    public List<IndexedPlace> indexedCandidates(String region, String category, String source, Boolean activeFestival) {
        List<IndexedPlace> candidates = findAll();
        if (region != null && !region.isBlank()) {
            candidates = intersect(candidates, findByRegion(region));
        }
        if (category != null && !category.isBlank()) {
            candidates = intersect(candidates, findByCategory(category));
        }
        if (source != null && !source.isBlank()) {
            candidates = intersect(candidates, findBySource(source));
        }
        if (activeFestival != null) {
            candidates = intersect(candidates, findByActiveFestival(activeFestival));
        }
        return candidates;
    }


    private interface IndexKeyExtractor {
        String key(IndexedPlace place);
    }

    private Map<String, List<IndexedPlace>> buildIndex(List<IndexedPlace> indexedPlaces, IndexKeyExtractor extractor) {
        Map<String, List<IndexedPlace>> mutable = new LinkedHashMap<>();
        for (IndexedPlace place : indexedPlaces) {
            String key = extractor.key(place);
            if (key == null || key.isBlank()) {
                continue;
            }
            mutable.computeIfAbsent(key, ignored -> new ArrayList<>()).add(place);
        }
        return copyIndex(mutable);
    }

    private Map<Boolean, List<IndexedPlace>> buildActiveFestivalIndex(List<IndexedPlace> indexedPlaces) {
        Map<Boolean, List<IndexedPlace>> mutable = new LinkedHashMap<>();
        mutable.put(true, new ArrayList<>());
        mutable.put(false, new ArrayList<>());
        LocalDate today = LocalDate.now();
        for (IndexedPlace place : indexedPlaces) {
            mutable.get(isActiveFestival(place, today)).add(place);
        }
        return Map.of(
                true, List.copyOf(mutable.get(true)),
                false, List.copyOf(mutable.get(false))
        );
    }

    private Map<String, List<IndexedPlace>> copyIndex(Map<String, List<IndexedPlace>> mutable) {
        Map<String, List<IndexedPlace>> copy = new LinkedHashMap<>();
        for (Map.Entry<String, List<IndexedPlace>> entry : mutable.entrySet()) {
            copy.put(entry.getKey(), List.copyOf(entry.getValue()));
        }
        return Map.copyOf(copy);
    }

    private List<IndexedPlace> findFromIndex(Map<String, List<IndexedPlace>> index, String key) {
        String normalized = normalizeIndexKey(key);
        if (normalized == null || normalized.isBlank()) {
            return List.of();
        }
        return index.getOrDefault(normalized, List.of());
    }

    private List<IndexedPlace> intersect(List<IndexedPlace> left, List<IndexedPlace> right) {
        if (left.isEmpty() || right.isEmpty()) {
            return List.of();
        }
        Set<String> rightIds = new LinkedHashSet<>();
        right.forEach(place -> rightIds.add(place.id()));
        return left.stream()
                .filter(place -> rightIds.contains(place.id()))
                .toList();
    }

    private boolean isActiveFestival(IndexedPlace place, LocalDate today) {
        if (place.tourApi() == null || place.tourApi().common() == null) {
            return false;
        }
        LocalDate start = parseTourDate(place.tourApi().common().eventStartDate());
        LocalDate end = parseTourDate(place.tourApi().common().eventEndDate());
        if (start == null && end == null) {
            return false;
        }
        if (start != null && today.isBefore(start)) {
            return false;
        }
        return end == null || !today.isAfter(end);
    }

    private LocalDate parseTourDate(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return LocalDate.parse(value.trim(), TOUR_DATE_FORMAT);
        } catch (DateTimeParseException ignored) {
            return null;
        }
    }

    private String normalizeIndexKey(String value) {
        return value == null ? null : value.trim().toLowerCase();
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

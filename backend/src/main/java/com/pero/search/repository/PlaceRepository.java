package com.pero.search.repository;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pero.search.model.IndexedPlace;
import com.pero.search.model.IndexedReview;
import com.pero.search.model.PlaceSeed;
import com.pero.search.service.EmbeddingService;
import com.pero.search.service.TextNormalizer;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Repository;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Repository
public class PlaceRepository {

    private final List<IndexedPlace> places;

    public PlaceRepository(
            ObjectMapper objectMapper,
            TextNormalizer normalizer,
            EmbeddingService embeddingService
    ) {
        this.places = loadPlaces(objectMapper, normalizer, embeddingService);
    }

    public List<IndexedPlace> findAll() {
        return places;
    }

    private List<IndexedPlace> loadPlaces(
            ObjectMapper objectMapper,
            TextNormalizer normalizer,
            EmbeddingService embeddingService
    ) {
        try (InputStream inputStream = new ClassPathResource("data/places.json").getInputStream()) {
            List<PlaceSeed> seeds = objectMapper.readValue(inputStream, new TypeReference<>() {
            });

            List<IndexedPlace> indexedPlaces = new ArrayList<>();
            for (PlaceSeed seed : seeds) {
                List<String> tags = seed.tags() == null ? List.of() : List.copyOf(seed.tags());
                List<String> reviewSentences = seed.reviewSentences() == null ? List.of() : List.copyOf(seed.reviewSentences());

                String searchableText = String.join(
                        " ",
                        seed.name(),
                        seed.category(),
                        seed.district(),
                        seed.summary(),
                        String.join(" ", tags),
                        String.join(" ", reviewSentences)
                );

                List<String> searchableTokens = normalizer.tokenizeForSearch(searchableText);
                Map<String, Integer> termFrequencies = new LinkedHashMap<>();
                for (String token : searchableTokens) {
                    termFrequencies.merge(token, 1, Integer::sum);
                }

                Set<String> featureTokens = new LinkedHashSet<>(normalizer.tokenizeForSearch(seed.summary()));
                tags.forEach(tag -> featureTokens.addAll(normalizer.tokenizeForSearch(tag)));

                List<IndexedReview> indexedReviews = reviewSentences.stream()
                        .map(sentence -> new IndexedReview(sentence, embeddingService.embed(sentence)))
                        .toList();

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
                        indexedReviews,
                        Collections.unmodifiableMap(termFrequencies),
                        Collections.unmodifiableSet(featureTokens),
                        searchableTokens.size(),
                        embeddingService.embed(searchableText)
                ));
            }
            return List.copyOf(indexedPlaces);
        } catch (IOException exception) {
            throw new UncheckedIOException("샘플 장소 데이터를 불러오지 못했습니다.", exception);
        }
    }
}

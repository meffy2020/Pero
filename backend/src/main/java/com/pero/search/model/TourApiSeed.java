package com.pero.search.model;

import java.util.List;
import java.util.Map;

public record TourApiSeed(
        String contentId,
        String contentTypeId,
        String contentTypeLabel,
        TourCommonSeed common,
        Map<String, String> intro,
        List<TourImageSeed> images,
        TourPetSeed pet
) {
}

package com.pero.search.dto;

import java.util.List;
import java.util.Map;

public record TourApiResponse(
        String contentId,
        String contentTypeId,
        String contentTypeLabel,
        TourCommonResponse common,
        Map<String, String> intro,
        List<TourImageResponse> images,
        TourPetResponse pet
) {
}

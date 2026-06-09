package com.pero.search.dto;

import java.time.OffsetDateTime;
import java.util.List;

public record PlacesResponse(
        SearchSourceMeta source,
        OffsetDateTime generatedAt,
        boolean fallbackUsed,
        String randomScope,
        boolean cacheMiss,
        int total,
        List<PlaceListItemResponse> places
) {
    public PlacesResponse(SearchSourceMeta source, int total, List<PlaceListItemResponse> places) {
        this(source, OffsetDateTime.now(), false, "요청 조건 안의 지도 후보", false, total, places);
    }
}

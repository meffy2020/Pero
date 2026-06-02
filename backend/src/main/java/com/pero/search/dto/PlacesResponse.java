package com.pero.search.dto;

import java.util.List;

public record PlacesResponse(
        SearchSourceMeta source,
        int total,
        List<PlaceListItemResponse> places
) {
}

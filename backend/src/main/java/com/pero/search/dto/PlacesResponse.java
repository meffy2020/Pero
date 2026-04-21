package com.pero.search.dto;

import java.util.List;
import java.util.Map;

public record PlacesResponse(
        SearchSourceMeta source,
        int total,
        List<Map<String, Object>> places
) {
}

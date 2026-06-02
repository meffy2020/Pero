package com.pero.search.dto;

import java.time.OffsetDateTime;
import java.util.List;

public record EventsResponse(
        OffsetDateTime generatedAt,
        int total,
        List<ThemeEventResponse> events
) {
}

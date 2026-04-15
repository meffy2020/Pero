package com.pero.search.dto;

import java.time.OffsetDateTime;

public record RecommendationResponse(
        OffsetDateTime generatedAt,
        boolean fallbackUsed,
        RecommendationCardResponse nearbyPick,
        RecommendationCardResponse mealPick,
        DateCourseResponse dateCourse
) {
}

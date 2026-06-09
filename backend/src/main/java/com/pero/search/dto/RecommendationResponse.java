package com.pero.search.dto;

import java.time.OffsetDateTime;

public record RecommendationResponse(
        OffsetDateTime generatedAt,
        SearchSourceMeta source,
        boolean fallbackUsed,
        String randomScope,
        RecommendationCardResponse nearbyPick,
        RecommendationCardResponse mealPick,
        DateCourseResponse dateCourse
) {
    public RecommendationResponse(
            OffsetDateTime generatedAt,
            boolean fallbackUsed,
            RecommendationCardResponse nearbyPick,
            RecommendationCardResponse mealPick,
            DateCourseResponse dateCourse
    ) {
        this(generatedAt, null, fallbackUsed, fallbackUsed ? "후보 부족으로 범위를 확장했습니다." : "요청 범위 안에서 랜덤", nearbyPick, mealPick, dateCourse);
    }
}

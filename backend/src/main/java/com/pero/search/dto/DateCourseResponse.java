package com.pero.search.dto;

import java.util.List;

public record DateCourseResponse(
        String title,
        String description,
        List<DateCourseStopResponse> stops
) {
}

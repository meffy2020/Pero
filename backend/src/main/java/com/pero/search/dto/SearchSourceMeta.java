package com.pero.search.dto;

import java.time.OffsetDateTime;

public record SearchSourceMeta(
        String providerId,
        String providerName,
        String status,
        OffsetDateTime generatedAt,
        int count
) {
}

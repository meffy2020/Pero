package com.pero.search.model;

public record IndexedReview(
        String sentence,
        double[] embedding
) {
}

package com.lumo.search.model;

public record IndexedReview(
        String sentence,
        double[] embedding
) {
}

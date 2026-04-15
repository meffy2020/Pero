package com.pero.search.model;

public record IndexedEvidence(
        String text,
        double[] embedding
) {
}

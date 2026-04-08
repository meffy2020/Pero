package com.pero.search.service;

import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class EmbeddingService {

    private static final int DIMENSION = 96;

    private final TextNormalizer normalizer;

    public EmbeddingService(TextNormalizer normalizer) {
        this.normalizer = normalizer;
    }

    public double[] embed(String text) {
        List<String> tokens = normalizer.tokenizeForSearch(text);
        double[] vector = new double[DIMENSION];

        for (String token : tokens) {
            addFeature(vector, token, 1.0);
        }

        String compact = normalizer.compact(text);
        for (int index = 0; index < compact.length() - 1; index++) {
            addFeature(vector, compact.substring(index, index + 2), 0.35);
        }
        for (int index = 0; index < compact.length() - 2; index++) {
            addFeature(vector, compact.substring(index, index + 3), 0.2);
        }

        normalize(vector);
        return vector;
    }

    public double cosineSimilarity(double[] left, double[] right) {
        double dot = 0.0;
        double leftNorm = 0.0;
        double rightNorm = 0.0;

        for (int index = 0; index < DIMENSION; index++) {
            dot += left[index] * right[index];
            leftNorm += left[index] * left[index];
            rightNorm += right[index] * right[index];
        }

        if (leftNorm == 0.0 || rightNorm == 0.0) {
            return 0.0;
        }
        return dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm));
    }

    private void addFeature(double[] vector, String token, double weight) {
        int primaryIndex = Math.floorMod(token.hashCode(), DIMENSION);
        int secondaryIndex = Math.floorMod((token + "#lumo").hashCode(), DIMENSION);

        vector[primaryIndex] += weight;
        vector[secondaryIndex] += weight * 0.6;
    }

    private void normalize(double[] vector) {
        double magnitude = 0.0;
        for (double value : vector) {
            magnitude += value * value;
        }

        if (magnitude == 0.0) {
            return;
        }

        double length = Math.sqrt(magnitude);
        for (int index = 0; index < vector.length; index++) {
            vector[index] /= length;
        }
    }
}

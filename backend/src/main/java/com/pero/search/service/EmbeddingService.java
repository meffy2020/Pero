package com.pero.search.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class EmbeddingService {

    private static final Logger log = LoggerFactory.getLogger(EmbeddingService.class);
    private static final int LOCAL_DIMENSION = 96;
    private static final int DEFAULT_REMOTE_DIMENSION = 256;
    private static final int OPENAI_BATCH_SIZE = 64;

    private final TextNormalizer normalizer;
    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;
    private final boolean openAiEnabled;
    private final String openAiApiKey;
    private final String openAiModel;
    private final int openAiDimensions;
    private final URI embeddingsEndpoint;
    private final Path cacheFile;
    private final Map<String, double[]> diskCache;
    private final Object cacheWriteLock;

    public EmbeddingService(TextNormalizer normalizer) {
        this.normalizer = normalizer;
        this.objectMapper = null;
        this.httpClient = null;
        this.openAiEnabled = false;
        this.openAiApiKey = null;
        this.openAiModel = null;
        this.openAiDimensions = LOCAL_DIMENSION;
        this.embeddingsEndpoint = null;
        this.cacheFile = null;
        this.diskCache = new ConcurrentHashMap<>();
        this.cacheWriteLock = new Object();
    }

    @Autowired
    public EmbeddingService(
            TextNormalizer normalizer,
            ObjectMapper objectMapper,
            @Value("${pero.search.embedding.provider:auto}") String providerSetting,
            @Value("${pero.search.embedding.openai.api-key:${OPENAI_API_KEY:}}") String openAiApiKey,
            @Value("${pero.search.embedding.openai.base-url:https://api.openai.com}") String openAiBaseUrl,
            @Value("${pero.search.embedding.openai.model:text-embedding-3-small}") String openAiModel,
            @Value("${pero.search.embedding.openai.dimensions:256}") Integer openAiDimensions,
            @Value("${pero.search.embedding.cache-file:build/embedding-cache/openai-embeddings.jsonl}") String cacheFilePath
    ) {
        this.normalizer = normalizer;
        this.objectMapper = objectMapper;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(20))
                .build();
        this.openAiEnabled = resolveOpenAiEnabled(providerSetting, openAiApiKey);
        this.openAiApiKey = openAiApiKey == null ? "" : openAiApiKey.trim();
        this.openAiModel = openAiModel;
        this.openAiDimensions = openAiDimensions == null || openAiDimensions <= 0
                ? DEFAULT_REMOTE_DIMENSION
                : openAiDimensions;
        this.embeddingsEndpoint = URI.create(stripTrailingSlash(openAiBaseUrl) + "/v1/embeddings");
        this.cacheFile = Path.of(cacheFilePath);
        this.diskCache = new ConcurrentHashMap<>();
        this.cacheWriteLock = new Object();

        if (this.openAiEnabled) {
            loadDiskCache();
            log.info(
                    "Embedding provider=openai model={} dimensions={} cacheEntries={}",
                    this.openAiModel,
                    this.openAiDimensions,
                    this.diskCache.size()
            );
        } else {
            if ("openai".equalsIgnoreCase(providerSetting) && this.openAiApiKey.isBlank()) {
                log.warn("Embedding provider=openai requested but OPENAI_API_KEY is missing. Falling back to local embeddings.");
            } else {
                log.info("Embedding provider=local");
            }
        }
    }

    public double[] embed(String text) {
        if (text == null || text.isBlank()) {
            return zeroVector();
        }

        if (!openAiEnabled) {
            return embedLocal(text);
        }

        Map<String, double[]> embedded = embedAll(List.of(text));
        return embedded.getOrDefault(text, zeroVector());
    }

    public Map<String, double[]> embedAll(List<String> texts) {
        if (texts == null || texts.isEmpty()) {
            return Map.of();
        }

        Set<String> uniqueTexts = new LinkedHashSet<>();
        for (String text : texts) {
            if (text != null && !text.isBlank()) {
                uniqueTexts.add(text);
            }
        }
        if (uniqueTexts.isEmpty()) {
            return Map.of();
        }

        Map<String, double[]> resolved = new LinkedHashMap<>();
        if (!openAiEnabled) {
            for (String text : uniqueTexts) {
                resolved.put(text, embedLocal(text));
            }
            return Map.copyOf(resolved);
        }

        List<String> missing = new ArrayList<>();
        for (String text : uniqueTexts) {
            double[] cached = diskCache.get(cacheKey(text));
            if (cached != null) {
                resolved.put(text, cached);
            } else {
                missing.add(text);
            }
        }

        if (!missing.isEmpty()) {
            if (missing.size() > 1) {
                log.info("Fetching {} embeddings from OpenAI (cacheHits={}).", missing.size(), resolved.size());
            }
            Map<String, double[]> fetched = fetchRemoteEmbeddings(missing);
            resolved.putAll(fetched);
            appendCacheEntries(fetched);
        }

        Map<String, double[]> ordered = new LinkedHashMap<>();
        for (String text : uniqueTexts) {
            ordered.put(text, resolved.getOrDefault(text, zeroVector()));
        }
        return Map.copyOf(ordered);
    }

    public double cosineSimilarity(double[] left, double[] right) {
        if (left == null || right == null) {
            return 0.0;
        }

        int dimension = Math.min(left.length, right.length);
        double dot = 0.0;
        double leftNorm = 0.0;
        double rightNorm = 0.0;

        for (int index = 0; index < dimension; index++) {
            dot += left[index] * right[index];
            leftNorm += left[index] * left[index];
            rightNorm += right[index] * right[index];
        }

        if (leftNorm == 0.0 || rightNorm == 0.0) {
            return 0.0;
        }
        return dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm));
    }

    private boolean resolveOpenAiEnabled(String providerSetting, String openAiApiKey) {
        String normalizedProvider = providerSetting == null ? "auto" : providerSetting.trim().toLowerCase();
        boolean hasKey = openAiApiKey != null && !openAiApiKey.trim().isBlank();
        return switch (normalizedProvider) {
            case "openai" -> hasKey;
            case "local" -> false;
            default -> hasKey;
        };
    }

    private double[] embedLocal(String text) {
        List<String> tokens = normalizer.tokenizeForSearch(text);
        double[] vector = new double[LOCAL_DIMENSION];

        for (String token : tokens) {
            addLocalFeature(vector, token, 1.0);
        }

        String compact = normalizer.compact(text);
        for (int index = 0; index < compact.length() - 1; index++) {
            addLocalFeature(vector, compact.substring(index, index + 2), 0.35);
        }
        for (int index = 0; index < compact.length() - 2; index++) {
            addLocalFeature(vector, compact.substring(index, index + 3), 0.2);
        }

        normalize(vector);
        return vector;
    }

    private void addLocalFeature(double[] vector, String token, double weight) {
        int primaryIndex = Math.floorMod(token.hashCode(), LOCAL_DIMENSION);
        int secondaryIndex = Math.floorMod((token + "#lumo").hashCode(), LOCAL_DIMENSION);

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

    private Map<String, double[]> fetchRemoteEmbeddings(List<String> texts) {
        Map<String, double[]> fetched = new LinkedHashMap<>();
        for (int start = 0; start < texts.size(); start += OPENAI_BATCH_SIZE) {
            List<String> batch = texts.subList(start, Math.min(start + OPENAI_BATCH_SIZE, texts.size()));
            fetched.putAll(fetchRemoteBatch(batch));
        }
        return fetched;
    }

    private Map<String, double[]> fetchRemoteBatch(List<String> batch) {
        try {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("model", openAiModel);
            payload.put("input", batch);
            payload.put("encoding_format", "float");
            payload.put("dimensions", openAiDimensions);

            HttpRequest request = HttpRequest.newBuilder(embeddingsEndpoint)
                    .timeout(Duration.ofSeconds(60))
                    .header("Authorization", "Bearer " + openAiApiKey)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(payload), StandardCharsets.UTF_8))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new IllegalStateException("OpenAI embeddings request failed: HTTP " + response.statusCode() + " " + truncate(response.body()));
            }

            JsonNode root = objectMapper.readTree(response.body());
            JsonNode data = root.path("data");
            if (!data.isArray()) {
                throw new IllegalStateException("OpenAI embeddings response is missing data array.");
            }

            double[][] vectors = new double[batch.size()][];
            for (JsonNode item : data) {
                int index = item.path("index").asInt(-1);
                if (index < 0 || index >= batch.size()) {
                    continue;
                }
                vectors[index] = toVector(item.path("embedding"));
            }

            Map<String, double[]> embeddings = new LinkedHashMap<>();
            for (int index = 0; index < batch.size(); index++) {
                embeddings.put(batch.get(index), vectors[index] == null ? zeroVector() : vectors[index]);
            }
            return embeddings;
        } catch (IOException | InterruptedException exception) {
            if (exception instanceof InterruptedException) {
                Thread.currentThread().interrupt();
            }
            throw new IllegalStateException("Failed to fetch OpenAI embeddings.", exception);
        }
    }

    private double[] toVector(JsonNode embeddingNode) {
        if (!embeddingNode.isArray()) {
            return zeroVector();
        }

        double[] vector = new double[embeddingNode.size()];
        for (int index = 0; index < embeddingNode.size(); index++) {
            vector[index] = embeddingNode.get(index).asDouble();
        }
        return vector;
    }

    private double[] zeroVector() {
        return new double[openAiEnabled ? openAiDimensions : LOCAL_DIMENSION];
    }

    private void loadDiskCache() {
        if (cacheFile == null || !Files.exists(cacheFile)) {
            return;
        }

        try (BufferedReader reader = Files.newBufferedReader(cacheFile, StandardCharsets.UTF_8)) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank()) {
                    continue;
                }
                JsonNode node = objectMapper.readTree(line);
                String key = node.path("key").asText("");
                JsonNode embeddingNode = node.path("embedding");
                if (key.isBlank() || !embeddingNode.isArray()) {
                    continue;
                }
                diskCache.putIfAbsent(key, toVector(embeddingNode));
            }
        } catch (IOException exception) {
            throw new IllegalStateException("Failed to load embedding cache file: " + cacheFile, exception);
        }
    }

    private void appendCacheEntries(Map<String, double[]> fetched) {
        if (fetched.isEmpty() || cacheFile == null) {
            return;
        }

        try {
            Path parent = cacheFile.getParent();
            if (parent != null) {
                Files.createDirectories(parent);
            }
        } catch (IOException exception) {
            throw new IllegalStateException("Failed to create embedding cache directory.", exception);
        }

        synchronized (cacheWriteLock) {
            try (BufferedWriter writer = Files.newBufferedWriter(
                    cacheFile,
                    StandardCharsets.UTF_8,
                    java.nio.file.StandardOpenOption.CREATE,
                    java.nio.file.StandardOpenOption.APPEND
            )) {
                for (Map.Entry<String, double[]> entry : fetched.entrySet()) {
                    String key = cacheKey(entry.getKey());
                    if (diskCache.putIfAbsent(key, entry.getValue()) != null) {
                        continue;
                    }

                    Map<String, Object> record = Map.of(
                            "key", key,
                            "embedding", entry.getValue()
                    );
                    writer.write(objectMapper.writeValueAsString(record));
                    writer.newLine();
                }
            } catch (IOException exception) {
                throw new IllegalStateException("Failed to write embedding cache file: " + cacheFile, exception);
            }
        }

        log.info("Embedding cache updated: +{} entries -> {}", fetched.size(), cacheFile);
    }

    private String cacheKey(String text) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hashed = digest.digest((openAiModel + ":" + openAiDimensions + ":" + text).getBytes(StandardCharsets.UTF_8));
            StringBuilder builder = new StringBuilder(hashed.length * 2);
            for (byte value : hashed) {
                builder.append(String.format("%02x", value));
            }
            return builder.toString();
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is not available.", exception);
        }
    }

    private String stripTrailingSlash(String value) {
        if (value == null || value.isBlank()) {
            return "https://api.openai.com";
        }
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }

    private String truncate(String body) {
        if (body == null) {
            return "";
        }
        return body.length() <= 240 ? body : body.substring(0, 240) + "...";
    }
}

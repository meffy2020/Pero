package com.pero.search.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

class EmbeddingServiceTests {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @TempDir
    Path tempDir;

    @Test
    void openAiEmbeddingsAreCachedToDisk() throws Exception {
        AtomicInteger requestCount = new AtomicInteger();
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/embeddings", exchange -> handleEmbeddings(exchange, requestCount));
        server.start();

        Path cacheFile = tempDir.resolve("embeddings.jsonl");
        String baseUrl = "http://127.0.0.1:" + server.getAddress().getPort();
        TextNormalizer normalizer = new TextNormalizer();

        EmbeddingService firstService = new EmbeddingService(
                normalizer,
                objectMapper,
                "openai",
                "test-key",
                baseUrl,
                "text-embedding-3-small",
                4,
                cacheFile.toString()
        );

        Map<String, double[]> firstResult = firstService.embedAll(List.of("서울 축제", "가족 나들이", "서울 축제"));

        assertThat(requestCount.get()).isEqualTo(1);
        assertThat(firstResult).hasSize(2);
        assertThat(firstResult.get("서울 축제")).containsExactly(2.0, 3.0, 4.0, 5.0);
        assertThat(firstResult.get("가족 나들이")).containsExactly(3.0, 4.0, 5.0, 6.0);

        server.stop(0);

        EmbeddingService cachedService = new EmbeddingService(
                normalizer,
                objectMapper,
                "openai",
                "test-key",
                "http://127.0.0.1:9",
                "text-embedding-3-small",
                4,
                cacheFile.toString()
        );

        Map<String, double[]> cachedResult = cachedService.embedAll(List.of("서울 축제", "가족 나들이"));

        assertThat(cachedResult.get("서울 축제")).containsExactly(2.0, 3.0, 4.0, 5.0);
        assertThat(cachedResult.get("가족 나들이")).containsExactly(3.0, 4.0, 5.0, 6.0);
    }

    private void handleEmbeddings(HttpExchange exchange, AtomicInteger requestCount) throws IOException {
        requestCount.incrementAndGet();
        JsonNode request = objectMapper.readTree(exchange.getRequestBody().readAllBytes());
        JsonNode inputs = request.path("input");

        StringBuilder response = new StringBuilder();
        response.append("{\"data\":[");
        for (int index = 0; index < inputs.size(); index++) {
            if (index > 0) {
                response.append(',');
            }
            int seed = inputs.get(index).asText().contains("가족") ? 3 : 2;
            response.append("{\"object\":\"embedding\",\"index\":")
                    .append(index)
                    .append(",\"embedding\":[")
                    .append(seed).append(',')
                    .append(seed + 1).append(',')
                    .append(seed + 2).append(',')
                    .append(seed + 3)
                    .append("]}");
        }
        response.append("],\"model\":\"text-embedding-3-small\"}");

        byte[] payload = response.toString().getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().add("Content-Type", "application/json");
        exchange.sendResponseHeaders(200, payload.length);
        try (OutputStream outputStream = exchange.getResponseBody()) {
            outputStream.write(payload);
        }
    }
}

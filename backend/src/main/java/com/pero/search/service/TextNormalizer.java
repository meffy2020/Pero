package com.pero.search.service;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Component
public class TextNormalizer {

    private static final Pattern TOKEN_PATTERN = Pattern.compile("[가-힣A-Za-z0-9]+");

    private static final Map<String, List<String>> SEMANTIC_HINTS = createSemanticHints();

    public String normalize(String source) {
        if (source == null || source.isBlank()) {
            return "";
        }
        return source.toLowerCase()
                .replaceAll("[^가-힣a-z0-9\\s]", " ")
                .replaceAll("\\s+", " ")
                .trim();
    }

    public String compact(String source) {
        return normalize(source).replace(" ", "");
    }

    public List<String> tokenize(String source) {
        String normalized = normalize(source);
        if (normalized.isBlank()) {
            return List.of();
        }

        Matcher matcher = TOKEN_PATTERN.matcher(normalized);
        List<String> tokens = new ArrayList<>();
        while (matcher.find()) {
            tokens.add(matcher.group());
        }
        return List.copyOf(tokens);
    }

    public List<String> tokenizeForSearch(String source) {
        List<String> baseTokens = tokenize(source);
        Set<String> expandedTokens = new LinkedHashSet<>(baseTokens);

        for (String token : baseTokens) {
            SEMANTIC_HINTS.forEach((key, values) -> {
                if (token.contains(key) || key.contains(token)) {
                    expandedTokens.addAll(values);
                }
            });
        }

        return List.copyOf(expandedTokens);
    }

    private static Map<String, List<String>> createSemanticHints() {
        Map<String, List<String>> hints = new LinkedHashMap<>();
        hints.put("조용", List.of("한적", "차분", "집중", "북카페"));
        hints.put("공부", List.of("집중", "노트북", "콘센트", "작업"));
        hints.put("카공", List.of("공부", "집중", "노트북", "콘센트"));
        hints.put("아이", List.of("가족", "유아", "어린이", "키즈"));
        hints.put("가족", List.of("아이", "유아", "어린이", "주말"));
        hints.put("반려동물", List.of("애견", "펫", "강아지", "동반"));
        hints.put("애견", List.of("반려동물", "펫", "강아지", "동반"));
        hints.put("브런치", List.of("샐러드", "베이커리", "커피", "주말"));
        hints.put("디저트", List.of("베이커리", "케이크", "커피"));
        hints.put("뷰", List.of("창가", "한강", "분위기"));
        hints.put("데이트", List.of("분위기", "야간", "와인"));
        return Map.copyOf(hints);
    }
}

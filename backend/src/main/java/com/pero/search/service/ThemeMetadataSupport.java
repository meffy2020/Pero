package com.pero.search.service;

import com.pero.search.model.TourApiSeed;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public final class ThemeMetadataSupport {

    private ThemeMetadataSupport() {
    }

    public static List<String> deriveThemeTags(
            String name,
            String category,
            String district,
            String summary,
            List<String> tags,
            List<String> searchHints,
            TourApiSeed tourApi
    ) {
        String haystack = String.join(
                " ",
                safe(name),
                safe(category),
                safe(district),
                safe(summary),
                String.join(" ", tags == null ? List.of() : tags),
                String.join(" ", searchHints == null ? List.of() : searchHints),
                safe(tourApi != null && tourApi.common() != null ? tourApi.common().overview() : null),
                safe(tourApi != null && tourApi.common() != null ? tourApi.common().useTime() : null),
                safe(tourApi != null && tourApi.common() != null ? tourApi.common().parking() : null),
                safe(tourApi != null && tourApi.pet() != null ? tourApi.pet().petTursmInfo() : null)
        ).toLowerCase(Locale.ROOT);

        Set<String> themeTags = new LinkedHashSet<>();

        if (safe(district).contains("서울")) {
            themeTags.add("서울");
        }

        if (hasEvent(tourApi) || containsAny(haystack, "행사", "축제", "공연", "페스티벌")) {
            themeTags.add("축제행사");
        }
        if (containsAny(haystack, "산책", "공원", "숲", "수목원", "정원", "둘레길", "전망", "야경", "한강", "해변", "호수", "바다", "생태", "자연", "힐링")) {
            themeTags.add("자연산책");
        }
        if (containsAny(haystack, "문화", "전시", "박물관", "미술", "공연", "실내", "관람", "쇼핑", "백화점", "라운지")) {
            themeTags.add("실내데이트");
        }
        if (containsAny(haystack, "가족", "아이", "키즈", "체험", "동물", "놀이", "캠핑")) {
            themeTags.add("가족나들이");
        }
        if (isPetFriendly(haystack, tourApi)) {
            themeTags.add("반려동물동반");
        }
        if (isAccessibleCandidate(haystack, tourApi)) {
            themeTags.add("무장애여행");
        }

        return List.copyOf(themeTags);
    }

    public static boolean hasEvent(TourApiSeed tourApi) {
        return tourApi != null
                && tourApi.common() != null
                && (!safe(tourApi.common().eventStartDate()).isBlank() || !safe(tourApi.common().eventEndDate()).isBlank());
    }

    public static boolean isPetFriendly(String haystack, TourApiSeed tourApi) {
        return containsAny(haystack, "반려", "애견", "펫", "동반 가능")
                || (tourApi != null
                && tourApi.pet() != null
                && (!safe(tourApi.pet().petTursmInfo()).isBlank() || !safe(tourApi.pet().acmpyPsblCpam()).isBlank()));
    }

    public static boolean isAccessibleCandidate(String haystack, TourApiSeed tourApi) {
        if (containsAny(haystack, "무장애", "휠체어", "유아차", "장애", "열린관광")) {
            return true;
        }
        return tourApi != null
                && tourApi.common() != null
                && !safe(tourApi.common().parking()).isBlank()
                && containsAny(haystack, "실내", "문화", "전시", "관광", "공원", "상시 개방");
    }

    private static boolean containsAny(String haystack, String... needles) {
        for (String needle : needles) {
            if (haystack.contains(needle.toLowerCase(Locale.ROOT))) {
                return true;
            }
        }
        return false;
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}

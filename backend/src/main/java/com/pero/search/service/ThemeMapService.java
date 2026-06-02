package com.pero.search.service;

import com.pero.search.dto.EventsResponse;
import com.pero.search.dto.ThemeCenterResponse;
import com.pero.search.dto.ThemeDetailResponse;
import com.pero.search.dto.ThemeEventResponse;
import com.pero.search.dto.ThemePlaceResponse;
import com.pero.search.dto.ThemeSummaryResponse;
import com.pero.search.dto.TourApiResponse;
import com.pero.search.dto.TourCommonResponse;
import com.pero.search.dto.TourImageResponse;
import com.pero.search.dto.TourPetResponse;
import com.pero.search.model.EventSeed;
import com.pero.search.model.IndexedPlace;
import com.pero.search.model.ThemeSeed;
import com.pero.search.model.TourApiSeed;
import com.pero.search.repository.PlaceRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class ThemeMapService {

    private static final DateTimeFormatter EVENT_DATE = DateTimeFormatter.BASIC_ISO_DATE;

    private final PlaceRepository placeRepository;
    private final TextNormalizer normalizer;
    private final Map<String, ThemeSeed> themeCatalog;

    public ThemeMapService(PlaceRepository placeRepository, TextNormalizer normalizer) {
        this.placeRepository = placeRepository;
        this.normalizer = normalizer;
        this.themeCatalog = createThemeCatalog();
    }

    public List<ThemeSummaryResponse> themes() {
        return themeCatalog.values().stream()
                .map(theme -> {
                    List<IndexedPlace> places = placesForTheme(theme.themeId(), 3);
                    int heroEventCount = (int) buildEventsForTheme(theme.themeId()).stream()
                            .filter(event -> !"ENDED".equals(eventStatus(event, LocalDate.now())))
                            .count();
                    return new ThemeSummaryResponse(
                            theme.themeId(),
                            theme.title(),
                            theme.scope(),
                            theme.source(),
                            theme.badge(),
                            theme.summary(),
                            places.stream().map(place -> toThemePlaceResponse(place, themeReason(theme, place))).toList(),
                            heroEventCount
                    );
                })
                .toList();
    }

    public ThemeDetailResponse theme(String themeId) {
        ThemeSeed theme = requiredTheme(themeId);
        List<IndexedPlace> places = placesForTheme(themeId, placeRepository.findAll().size());
        List<ThemeEventResponse> events = buildEventsForTheme(themeId).stream()
                .limit(20)
                .toList();
        Set<String> sourceAttributions = places.stream()
                .map(IndexedPlace::sourceAttribution)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        if (theme.smartSeoulLayerEnabled()) {
            sourceAttributions.add("merged");
        }

        return new ThemeDetailResponse(
                theme.themeId(),
                theme.title(),
                theme.scope(),
                theme.source(),
                theme.badge(),
                theme.summary(),
                OffsetDateTime.now(),
                new ThemeCenterResponse(theme.latitude(), theme.longitude()),
                theme.smartSeoulLayerEnabled(),
                List.copyOf(sourceAttributions),
                places.stream().map(place -> toThemePlaceResponse(place, themeReason(theme, place))).toList(),
                events
        );
    }

    public EventsResponse events(String region, String themeId, LocalDate activeOn, Integer limit) {
        int resolvedLimit = limit == null || limit < 1 ? 8 : Math.min(limit, 30);
        List<ThemeEventResponse> events = themeId == null || themeId.isBlank()
                ? buildAllEvents()
                : buildEventsForTheme(themeId);

        if (region != null && !region.isBlank()) {
            String normalizedRegion = normalizer.normalize(region);
            events = events.stream()
                    .filter(event -> matchesRegion(normalizedRegion, event))
                    .toList();
        }

        if (activeOn != null) {
            events = events.stream()
                    .filter(event -> "ACTIVE".equals(eventStatus(event, activeOn)))
                    .toList();
        } else {
            events = events.stream()
                    .filter(event -> {
                        String status = eventStatus(event, LocalDate.now());
                        return "ACTIVE".equals(status) || "UPCOMING".equals(status);
                    })
                    .toList();
        }

        List<ThemeEventResponse> limited = events.stream()
                .limit(resolvedLimit)
                .toList();

        return new EventsResponse(OffsetDateTime.now(), limited.size(), limited);
    }

    public List<IndexedPlace> filterPlacesByTheme(List<IndexedPlace> places, String themeId) {
        if (themeId == null || themeId.isBlank()) {
            return places;
        }
        ThemeSeed theme = requiredTheme(themeId);

        List<IndexedPlace> matched = places.stream()
                .filter(place -> matchesTheme(place, themeId))
                .toList();
        int minimumCount = minimumPlacesForTheme(theme);
        if (matched.size() >= minimumCount) {
            return matched;
        }

        List<IndexedPlace> fallback = places.stream()
                .filter(place -> !"seoul".equals(theme.scope()) || isSeoulPlace(place))
                .sorted(Comparator.comparingDouble((IndexedPlace place) -> fallbackWeight(theme, place)).reversed())
                .toList();

        if (matched.isEmpty()) {
            return fallback.stream()
                    .limit(Math.min(Math.max(places.size(), 1), minimumCount))
                    .toList();
        }

        LinkedHashSet<IndexedPlace> merged = new LinkedHashSet<>(matched);
        for (IndexedPlace candidate : fallback) {
            if (merged.size() >= minimumCount) {
                break;
            }
            merged.add(candidate);
        }
        return List.copyOf(merged);
    }

    public boolean matchesTheme(IndexedPlace place, String themeId) {
        ThemeSeed theme = requiredTheme(themeId);
        String haystack = normalizedHaystack(place);
        boolean isSeoul = isSeoulPlace(place);
        boolean isEvent = ThemeMetadataSupport.hasEvent(place.tourApi()) || place.themeTags().contains("축제행사");
        boolean isNature = place.themeTags().contains("자연산책") || containsAny(haystack, "산책", "공원", "숲", "수목원", "정원", "전망", "한강", "해변", "바다", "호수", "둘레길");
        boolean isIndoor = place.themeTags().contains("실내데이트") || containsAny(haystack, "문화", "전시", "박물관", "미술", "공연", "실내", "관람", "쇼핑", "도서관", "복합문화");
        boolean isPet = place.themeTags().contains("반려동물동반") || ThemeMetadataSupport.isPetFriendly(haystack, place.tourApi());
        boolean isAccessible = place.themeTags().contains("무장애여행") || ThemeMetadataSupport.isAccessibleCandidate(haystack, place.tourApi());
        boolean isFamily = place.themeTags().contains("가족나들이") || containsAny(haystack, "가족", "아이", "키즈", "체험", "놀이터", "동물");

        return switch (theme.themeId()) {
            case "seoul-events" -> isSeoul && isEvent;
            case "seoul-night-walk" -> isSeoul && (isNature || containsAny(haystack, "야경", "전망", "한강", "도보"));
            case "seoul-indoor-date" -> isSeoul && isIndoor;
            case "seoul-pet" -> isSeoul && isPet;
            case "seoul-accessible" -> isSeoul && isAccessible;
            case "nationwide-festival" -> isEvent;
            case "nationwide-nature" -> isNature;
            case "nationwide-culture" -> isIndoor;
            case "nationwide-family" -> isFamily || isNature;
            case "nationwide-pet" -> isPet;
            case "nationwide-accessible" -> isAccessible;
            default -> false;
        };
    }

    private List<IndexedPlace> placesForTheme(String themeId, int limit) {
        ThemeSeed theme = requiredTheme(themeId);
        List<IndexedPlace> allPlaces = placeRepository.findAll();
        List<IndexedPlace> matched = filterPlacesByTheme(allPlaces, themeId);
        return matched.stream()
                .sorted(Comparator.comparingDouble((IndexedPlace place) -> themeWeight(theme, place)).reversed())
                .limit(limit)
                .toList();
    }

    private List<ThemeEventResponse> buildAllEvents() {
        return themeCatalog.values().stream()
                .flatMap(theme -> buildEventsForTheme(theme.themeId()).stream())
                .collect(Collectors.toMap(
                        ThemeEventResponse::id,
                        event -> event,
                        (left, right) -> left,
                        LinkedHashMap::new
                ))
                .values()
                .stream()
                .sorted(this::compareEvents)
                .toList();
    }

    private List<ThemeEventResponse> buildEventsForTheme(String themeId) {
        ThemeSeed theme = requiredTheme(themeId);
        return placeRepository.findAll().stream()
                .filter(place -> matchesTheme(place, themeId))
                .map(place -> toEventSeed(place))
                .filter(event -> event != null)
                .sorted(this::compareEventSeeds)
                .map(event -> toThemeEventResponse(theme, event))
                .toList();
    }

    private EventSeed toEventSeed(IndexedPlace place) {
        TourApiSeed tourApi = place.tourApi();
        if (!ThemeMetadataSupport.hasEvent(tourApi) || tourApi == null || tourApi.common() == null) {
            return null;
        }

        LocalDate startDate = parseEventDate(tourApi.common().eventStartDate());
        LocalDate endDate = parseEventDate(tourApi.common().eventEndDate());
        if (startDate == null && endDate == null) {
            return null;
        }

        return new EventSeed(
                "event-" + place.id(),
                place.name(),
                startDate,
                endDate,
                place.district(),
                place.name(),
                place.latitude(),
                place.longitude(),
                tourApi.common().overview() == null || tourApi.common().overview().isBlank() ? place.summary() : tourApi.common().overview(),
                place.sourceAttribution(),
                place.id()
        );
    }

    private ThemeEventResponse toThemeEventResponse(ThemeSeed theme, EventSeed event) {
        return new ThemeEventResponse(
                event.id(),
                event.title(),
                eventStatus(event, LocalDate.now()),
                formatEventDate(event.startDate()),
                formatEventDate(event.endDate()),
                formatPeriodLabel(event.startDate(), event.endDate()),
                event.district(),
                event.venue(),
                event.latitude(),
                event.longitude(),
                event.sourceAttribution(),
                event.summary(),
                theme.themeId(),
                event.relatedPlaceId()
        );
    }

    private ThemePlaceResponse toThemePlaceResponse(IndexedPlace place, String reason) {
        return new ThemePlaceResponse(
                place.id(),
                place.name(),
                place.category(),
                place.district(),
                place.address(),
                place.roadAddress(),
                place.summary(),
                place.tags(),
                place.themeTags(),
                place.latitude(),
                place.longitude(),
                place.sourceAttribution(),
                reason,
                toTourApiResponse(place.tourApi())
        );
    }

    private ThemeSeed requiredTheme(String themeId) {
        ThemeSeed theme = themeCatalog.get(themeId);
        if (theme == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "존재하지 않는 themeId입니다: " + themeId);
        }
        return theme;
    }

    private Map<String, ThemeSeed> createThemeCatalog() {
        List<ThemeSeed> themes = List.of(
                new ThemeSeed("seoul-events", "서울 행사", "seoul", "merged", "SEOUL LIVE", "서울 권역에서 진행 중이거나 곧 시작되는 행사와 축제를 우선 보여줍니다.", 37.5665, 126.9780, true, 1),
                new ThemeSeed("seoul-night-walk", "야간 산책", "seoul", "merged", "SEOUL WALK", "서울 야경, 산책, 전망 포인트를 중심으로 밤 산책 테마를 구성합니다.", 37.5704, 126.9910, true, 2),
                new ThemeSeed("seoul-indoor-date", "실내 데이트", "seoul", "merged", "SEOUL INDOOR", "서울에서 비 오는 날에도 보기 좋은 실내 문화/전시 중심 코스를 묶습니다.", 37.5725, 126.9769, true, 3),
                new ThemeSeed("seoul-pet", "반려동물 동반", "seoul", "merged", "SEOUL PET", "서울에서 반려동물과 함께 움직이기 쉬운 장소를 우선 큐레이션합니다.", 37.5665, 126.9780, true, 4),
                new ThemeSeed("seoul-accessible", "무장애 나들이", "seoul", "merged", "SEOUL ACCESS", "서울에서 접근성과 체류 편의가 상대적으로 높은 장소를 우선 보여줍니다.", 37.5665, 126.9780, true, 5),
                new ThemeSeed("nationwide-festival", "축제/행사", "nationwide", "koreaTour", "NATION FEST", "전국의 행사·공연·축제 장소를 우선 정렬해 시즌성 테마를 바로 볼 수 있게 합니다.", 36.5, 127.8, false, 6),
                new ThemeSeed("nationwide-nature", "자연/산책", "nationwide", "koreaTour", "NATION NATURE", "숲, 공원, 전망, 해안, 산책 중심 관광지를 전국 단위로 묶습니다.", 36.5, 127.8, false, 7),
                new ThemeSeed("nationwide-culture", "문화/전시", "nationwide", "koreaTour", "NATION CULTURE", "전시, 문화시설, 실내 관람 중심 관광지를 전국 단위로 보여줍니다.", 36.5, 127.8, false, 8),
                new ThemeSeed("nationwide-family", "가족 나들이", "nationwide", "koreaTour", "NATION FAMILY", "가족 단위 방문, 체험, 공원형 나들이에 맞는 장소를 큐레이션합니다.", 36.5, 127.8, false, 9),
                new ThemeSeed("nationwide-pet", "반려동물 동반", "nationwide", "koreaTour", "NATION PET", "반려동물 동반 가능성이 높은 전국 관광지를 추립니다.", 36.5, 127.8, false, 10),
                new ThemeSeed("nationwide-accessible", "무장애 여행", "nationwide", "koreaTour", "NATION ACCESS", "접근성 힌트가 있는 전국 관광지를 우선 보여줍니다.", 36.5, 127.8, false, 11)
        );

        return themes.stream()
                .sorted(Comparator.comparingInt(ThemeSeed::priority))
                .collect(Collectors.toMap(ThemeSeed::themeId, theme -> theme, (left, right) -> left, LinkedHashMap::new));
    }

    private double themeWeight(ThemeSeed theme, IndexedPlace place) {
        double score = fallbackWeight(theme, place);
        if (matchesTheme(place, theme.themeId())) {
            score += 3.5;
        }
        if (theme.smartSeoulLayerEnabled() && place.district().contains("서울")) {
            score += 1.5;
        }
        return score;
    }

    private double fallbackWeight(ThemeSeed theme, IndexedPlace place) {
        double score = 0.0;
        if ("seoul".equals(theme.scope()) && isSeoulPlace(place)) {
            score += 2.0;
        }
        if ("nationwide".equals(theme.scope()) && !place.district().isBlank()) {
            score += 1.0;
        }
        if (place.tourApi() != null && place.tourApi().images() != null && !place.tourApi().images().isEmpty()) {
            score += 0.8;
        }
        if (place.tourApi() != null && place.tourApi().common() != null && place.tourApi().common().overview() != null && !place.tourApi().common().overview().isBlank()) {
            score += 0.5;
        }
        if (!place.themeTags().isEmpty()) {
            score += 0.2 * place.themeTags().size();
        }
        return score;
    }

    private int minimumPlacesForTheme(ThemeSeed theme) {
        if ("seoul".equals(theme.scope())) {
            return 24;
        }
        return 36;
    }

    private String themeReason(ThemeSeed theme, IndexedPlace place) {
        if (matchesTheme(place, theme.themeId())) {
            return switch (theme.themeId()) {
                case "seoul-events", "nationwide-festival" -> "행사/축제 일정이 연결된 장소라 테마 대표 후보로 선정했습니다.";
                case "seoul-night-walk", "nationwide-nature" -> "산책·전망·야외 활동 맥락이 강해 테마에 맞는 후보로 분류했습니다.";
                case "seoul-indoor-date", "nationwide-culture" -> "실내 관람·문화 체류에 맞는 성격이라 테마 대표 후보로 선정했습니다.";
                case "seoul-pet", "nationwide-pet" -> "반려동물 동반 힌트가 있어 함께 움직이는 테마에 우선 배치했습니다.";
                case "seoul-accessible", "nationwide-accessible" -> "접근성 또는 체류 편의 힌트가 있어 무장애 테마 후보로 우선 배치했습니다.";
                case "nationwide-family" -> "가족·체험·여유 있는 방문 흐름에 맞는 후보로 분류했습니다.";
                default -> "테마와의 연결 신호가 높아 우선 노출했습니다.";
            };
        }
        return "현재 캐시에서 테마와 가까운 성격을 가진 대체 후보입니다.";
    }

    private String normalizedHaystack(IndexedPlace place) {
        return String.join(
                " ",
                place.name(),
                place.category(),
                place.district(),
                place.address(),
                place.roadAddress(),
                place.summary(),
                String.join(" ", place.tags()),
                String.join(" ", place.themeTags()),
                place.tourApi() != null && place.tourApi().common() != null ? safe(place.tourApi().common().overview()) : ""
        ).toLowerCase(Locale.ROOT);
    }

    private boolean matchesRegion(String normalizedRegion, ThemeEventResponse event) {
        if ("seoul".equals(normalizedRegion)) {
            return event.themeId().startsWith("seoul-") || event.district().contains("서울");
        }
        return normalizer.normalize(event.district()).contains(normalizedRegion);
    }

    private boolean isSeoulPlace(IndexedPlace place) {
        String regionHaystack = String.join(
                " ",
                safe(place.district()),
                safe(place.address()),
                safe(place.roadAddress())
        ).toLowerCase(Locale.ROOT);
        return containsAny(regionHaystack, "서울", "seoul");
    }

    private int compareEvents(ThemeEventResponse left, ThemeEventResponse right) {
        return compareEventDates(parseEventDate(left.startDate()), parseEventDate(right.startDate()));
    }

    private int compareEventSeeds(EventSeed left, EventSeed right) {
        return compareEventDates(left.startDate(), right.startDate());
    }

    private int compareEventDates(LocalDate left, LocalDate right) {
        if (left == null && right == null) {
            return 0;
        }
        if (left == null) {
            return 1;
        }
        if (right == null) {
            return -1;
        }
        return left.compareTo(right);
    }

    private String eventStatus(ThemeEventResponse event, LocalDate referenceDate) {
        return eventStatus(new EventSeed(
                event.id(),
                event.title(),
                parseEventDate(event.startDate()),
                parseEventDate(event.endDate()),
                event.district(),
                event.venue(),
                event.latitude(),
                event.longitude(),
                event.summary(),
                event.sourceAttribution(),
                event.relatedPlaceId()
        ), referenceDate);
    }

    private String eventStatus(EventSeed event, LocalDate referenceDate) {
        LocalDate startDate = event.startDate();
        LocalDate endDate = event.endDate();
        if (startDate != null && endDate != null) {
            if (referenceDate.isBefore(startDate)) {
                return "UPCOMING";
            }
            if (referenceDate.isAfter(endDate)) {
                return "ENDED";
            }
            return "ACTIVE";
        }
        if (startDate != null) {
            return referenceDate.isBefore(startDate) ? "UPCOMING" : "ACTIVE";
        }
        if (endDate != null) {
            return referenceDate.isAfter(endDate) ? "ENDED" : "ACTIVE";
        }
        return "UNKNOWN";
    }

    private LocalDate parseEventDate(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            if (value.contains("-")) {
                return LocalDate.parse(value);
            }
            return LocalDate.parse(value, EVENT_DATE);
        } catch (DateTimeParseException ignored) {
            return null;
        }
    }

    private String formatEventDate(LocalDate date) {
        return date == null ? null : date.toString();
    }

    private String formatPeriodLabel(LocalDate startDate, LocalDate endDate) {
        if (startDate == null && endDate == null) {
            return "일정 미정";
        }
        if (startDate != null && endDate != null) {
            return startDate + " ~ " + endDate;
        }
        if (startDate != null) {
            return startDate + " 시작";
        }
        return endDate + " 종료";
    }

    private boolean containsAny(String haystack, String... needles) {
        for (String needle : needles) {
            if (haystack.contains(needle.toLowerCase(Locale.ROOT))) {
                return true;
            }
        }
        return false;
    }

    private String safe(String value) {
        return value == null ? "" : value;
    }

    private TourApiResponse toTourApiResponse(TourApiSeed tourApi) {
        if (tourApi == null) {
            return null;
        }

        TourCommonResponse common = null;
        if (tourApi.common() != null) {
            common = new TourCommonResponse(
                    tourApi.common().tel(),
                    tourApi.common().homepage(),
                    tourApi.common().overview(),
                    tourApi.common().bookTour(),
                    tourApi.common().infoCenter(),
                    tourApi.common().restDate(),
                    tourApi.common().useTime(),
                    tourApi.common().parking(),
                    tourApi.common().useFee(),
                    tourApi.common().refundPolicy(),
                    tourApi.common().expGuide(),
                    tourApi.common().accomCount(),
                    tourApi.common().chkInTime(),
                    tourApi.common().chkOutTime(),
                    tourApi.common().subFacility(),
                    tourApi.common().parkingFee(),
                    tourApi.common().scale(),
                    tourApi.common().spendTime(),
                    tourApi.common().eventStartDate(),
                    tourApi.common().eventEndDate(),
                    tourApi.common().playTime(),
                    tourApi.common().ageLimit()
            );
        }

        return new TourApiResponse(
                tourApi.contentId(),
                tourApi.contentTypeId(),
                tourApi.contentTypeLabel(),
                common,
                tourApi.intro(),
                tourApi.images() == null ? List.of() : tourApi.images().stream()
                        .map(image -> new TourImageResponse(
                                image.originImgUrl(),
                                image.smallImageUrl(),
                                image.imgName(),
                                image.serialNum()
                        ))
                        .toList(),
                tourApi.pet() == null ? null : new TourPetResponse(
                        tourApi.pet().petTursmInfo(),
                        tourApi.pet().acmpyTypeCd(),
                        tourApi.pet().relaPosesFclty(),
                        tourApi.pet().relaFrnshPrdlst(),
                        tourApi.pet().etcAcmpyInfo(),
                        tourApi.pet().relaPurcPrdlst(),
                        tourApi.pet().acmpyPsblCpam()
                )
        );
    }
}

"use client";

import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import dynamic from "next/dynamic";
import styles from "./page.module.css";
import type {
  EventsResponse,
  PlaceComparisonItem,
  PlaceResult,
  SearchResponse,
  ThemeDetail,
  ThemeEvent,
  ThemePlace,
  ThemeSummary,
} from "./search-types";

const SearchMap = dynamic(
  () => import("./components/search-map").then((module) => module.SearchMap),
  {
    ssr: false,
    loading: () => <div className={styles.mapSkeleton}>지도를 불러오는 중입니다.</div>,
  },
);

type ThemeBootState = "loading" | "ready" | "error";
type ThemeDetailState = "idle" | "loading" | "ready" | "error";
type SearchOverrideState = "idle" | "loading" | "active" | "error";
const INITIAL_PLACE_LIST_LIMIT = 24;
const HTML_ENTITY_MAP: Record<string, string> = {
  "&nbsp;": " ",
  "&amp;": "&",
  "&quot;": '"',
  "&#39;": "'",
  "&lt;": "<",
  "&gt;": ">",
};

function sourceLabel(sourceAttribution: string | null | undefined): string {
  if (!sourceAttribution) {
    return "출처 미확인";
  }
  if (sourceAttribution === "merged") {
    return "스마트서울맵 + 한국관광공사";
  }
  if (sourceAttribution === "smartSeoul") {
    return "스마트서울맵";
  }
  if (sourceAttribution === "koreaTour") {
    return "한국관광공사";
  }
  return sourceAttribution;
}

function buildMapUrl(latitude: number, longitude: number): string {
  return `https://www.google.com/maps/search/?api=1&query=${latitude},${longitude}`;
}

function decodeHtmlEntities(value: string): string {
  return value.replace(/&nbsp;|&amp;|&quot;|&#39;|&lt;|&gt;/g, (entity) => HTML_ENTITY_MAP[entity] ?? entity);
}

function sanitizeRichText(value: string | null | undefined): string {
  if (!value) {
    return "";
  }

  return decodeHtmlEntities(
    value
      .replace(/<\s*br\s*\/?\s*>/gi, "\n")
      .replace(/<\/(p|div|li)>/gi, "\n")
      .replace(/<li[^>]*>/gi, "- ")
      .replace(/\s*※\s*/g, "\n※ ")
      .replace(/<[^>]+>/g, " "),
  )
    .replace(/\r/g, "")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

function metadataSegments(value: string | null | undefined): string[] {
  return sanitizeRichText(value)
    .split("\n")
    .map((segment) => segment.replace(/^[\s\-•]+/, "").trim())
    .filter(Boolean);
}

function labeledChips(label: string, value: string | null | undefined, limit: number): string[] {
  return metadataSegments(value)
    .slice(0, limit)
    .map((segment) => `${label} ${segment}`);
}

function getRepresentativeImageUrl(place: ThemePlace | PlaceResult | null): string | null {
  const image = place?.tourApi?.images?.find((item) => item.originImgUrl || item.smallImageUrl);
  return image?.originImgUrl ?? image?.smallImageUrl ?? null;
}

function toComparisonItem(place: ThemePlace | PlaceResult): PlaceComparisonItem {
  return {
    id: place.id,
    name: place.name,
    category: place.category,
    district: place.district,
    roadAddress: place.roadAddress,
    summary: place.summary,
    tags: place.tags,
    themeTags: place.themeTags,
    latitude: place.latitude,
    longitude: place.longitude,
    sourceAttribution: place.sourceAttribution,
    distanceKm: "distanceKm" in place ? place.distanceKm : null,
    reason: "reason" in place ? place.reason : null,
    evidence: "evidence" in place ? place.evidence : null,
    sourceLabel: sourceLabel(place.sourceAttribution),
    tourApi: place.tourApi,
  };
}

function buildMetaChips(place: ThemePlace | PlaceResult | null): string[] {
  if (!place) {
    return [];
  }

  const chips: string[] = [];
  const common = place.tourApi?.common;
  const pet = place.tourApi?.pet;

  if ("distanceKm" in place && place.distanceKm != null) {
    chips.push(`${place.distanceKm.toFixed(2)}km`);
  }
  chips.push(...labeledChips("운영", common?.useTime, 2));
  chips.push(...labeledChips("휴무", common?.restDate, 1));
  chips.push(...labeledChips("주차", common?.parking, 2));
  if (pet?.petTursmInfo || pet?.acmpyPsblCpam) {
    chips.push(...labeledChips("반려", pet.petTursmInfo ?? pet.acmpyPsblCpam, 1));
  }
  for (const tag of place.themeTags ?? []) {
    if (chips.length >= 4) {
      break;
    }
    const normalizedTag = sanitizeRichText(tag);
    if (!normalizedTag) {
      continue;
    }
    chips.push(normalizedTag);
  }

  return chips.slice(0, 4);
}

function buildSelectionChips(place: ThemePlace | PlaceResult | null): string[] {
  if (!place) {
    return [];
  }

  const common = place.tourApi?.common;
  const pet = place.tourApi?.pet;
  const chips = [`지역 ${sanitizeRichText(place.district)}`, `출처 ${sourceLabel(place.sourceAttribution)}`];

  if ("distanceKm" in place && place.distanceKm != null) {
    chips.push(`거리 ${place.distanceKm.toFixed(2)}km`);
  }

  chips.push(...labeledChips("운영", common?.useTime, 3));
  chips.push(...labeledChips("휴무", common?.restDate, 1));
  chips.push(...labeledChips("주차", common?.parking, 2));
  chips.push(...labeledChips("요금", common?.useFee, 1));

  if (pet?.petTursmInfo || pet?.acmpyPsblCpam) {
    chips.push(...labeledChips("반려", pet.petTursmInfo ?? pet.acmpyPsblCpam, 1));
  }

  return chips.filter(Boolean).slice(0, 8);
}

function selectedPlaceLead(place: ThemePlace | PlaceResult | null, fallback: string): string {
  if (!place) {
    return fallback;
  }
  if ("evidence" in place && place.evidence) {
    return sanitizeRichText(place.evidence);
  }
  if ("reason" in place && place.reason) {
    return sanitizeRichText(place.reason);
  }
  return sanitizeRichText(fallback);
}

export default function Home() {
  const [themeBootState, setThemeBootState] = useState<ThemeBootState>("loading");
  const [themeDetailState, setThemeDetailState] = useState<ThemeDetailState>("idle");
  const [searchState, setSearchState] = useState<SearchOverrideState>("idle");
  const [bootError, setBootError] = useState<string | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [themes, setThemes] = useState<ThemeSummary[]>([]);
  const [activeThemeId, setActiveThemeId] = useState<string | null>(null);
  const [themeDetail, setThemeDetail] = useState<ThemeDetail | null>(null);
  const [eventsResponse, setEventsResponse] = useState<EventsResponse | null>(null);
  const [query, setQuery] = useState("");
  const [searchResponse, setSearchResponse] = useState<SearchResponse | null>(null);
  const [selectedPlaceId, setSelectedPlaceId] = useState<string | null>(null);
  const [hoveredPlaceId, setHoveredPlaceId] = useState<string | null>(null);
  const [isPanelOpen, setIsPanelOpen] = useState(true);
  const [placeListLimit, setPlaceListLimit] = useState(INITIAL_PLACE_LIST_LIMIT);
  const resultItemRefs = useRef<Record<string, HTMLButtonElement | null>>({});

  useEffect(() => {
    let cancelled = false;

    async function bootThemes() {
      setThemeBootState("loading");
      setBootError(null);

      try {
        const result = await fetch("/api/themes");
        if (!result.ok) {
          throw new Error(`테마 목록 요청 실패 (${result.status})`);
        }

        const data = (await result.json()) as ThemeSummary[];
        if (cancelled) {
          return;
        }

        setThemes(data);
        setActiveThemeId(data[0]?.themeId ?? null);
        setThemeBootState("ready");
      } catch (error) {
        if (cancelled) {
          return;
        }
        setThemes([]);
        setActiveThemeId(null);
        setThemeBootState("error");
        setBootError(error instanceof Error ? error.message : "테마 목록을 불러오지 못했습니다.");
      }
    }

    void bootThemes();

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!activeThemeId) {
      setThemeDetailState(themeBootState === "error" ? "error" : "idle");
      setThemeDetail(null);
      setEventsResponse(null);
      setSearchResponse(null);
      setSelectedPlaceId(null);
      return;
    }

    let cancelled = false;

    async function loadTheme(themeId: string) {
      setThemeDetailState("loading");
      setDetailError(null);
      setSearchState("idle");
      setSearchError(null);
      setSearchResponse(null);
      setQuery("");
      setHoveredPlaceId(null);
      setPlaceListLimit(INITIAL_PLACE_LIST_LIMIT);

      try {
        const detailResult = await fetch(`/api/themes/${themeId}`);
        if (!detailResult.ok) {
          throw new Error(`테마 상세 요청 실패 (${detailResult.status})`);
        }

        const detail = (await detailResult.json()) as ThemeDetail;
        let events: EventsResponse = {
          generatedAt: detail.generatedAt,
          total: detail.events.length,
          events: detail.events,
        };

        try {
          const eventsResult = await fetch(`/api/events?themeId=${encodeURIComponent(themeId)}&limit=8`);
          if (eventsResult.ok) {
            events = (await eventsResult.json()) as EventsResponse;
          }
        } catch {
          // fall back to theme detail events
        }

        if (cancelled) {
          return;
        }

        setThemeDetail(detail);
        setEventsResponse(events);
        setSelectedPlaceId(null);
        setThemeDetailState("ready");
      } catch (error) {
        if (cancelled) {
          return;
        }
        setThemeDetail(null);
        setEventsResponse(null);
        setSelectedPlaceId(null);
        setThemeDetailState("error");
        setDetailError(error instanceof Error ? error.message : "테마를 불러오지 못했습니다.");
      }
    }

    void loadTheme(activeThemeId);

    return () => {
      cancelled = true;
    };
  }, [activeThemeId, themeBootState]);

  const activeTheme = useMemo(
    () => themes.find((theme) => theme.themeId === activeThemeId) ?? null,
    [themes, activeThemeId],
  );

  const activeEvents = useMemo(
    () => eventsResponse?.events ?? themeDetail?.events ?? [],
    [eventsResponse, themeDetail],
  );

  const activePlaces = useMemo<PlaceComparisonItem[]>(() => {
    const rawPlaces = searchResponse?.results ?? themeDetail?.places ?? [];
    return rawPlaces.map((place) => toComparisonItem(place));
  }, [searchResponse, themeDetail]);

  const visiblePlaces = useMemo(() => activePlaces.slice(0, placeListLimit), [activePlaces, placeListLimit]);

  const placeRecords = useMemo(() => {
    const records = new Map<string, ThemePlace | PlaceResult>();
    for (const place of themeDetail?.places ?? []) {
      records.set(place.id, place);
    }
    for (const place of searchResponse?.results ?? []) {
      records.set(place.id, place);
    }
    return records;
  }, [themeDetail, searchResponse]);

  const selectedPlace =
    (selectedPlaceId ? placeRecords.get(selectedPlaceId) : null) ??
    (visiblePlaces[0] ? placeRecords.get(visiblePlaces[0].id) : null) ??
    null;

  const selectedImage = getRepresentativeImageUrl(selectedPlace);
  const selectedEvents = useMemo(
    () => activeEvents.filter((item) => item.relatedPlaceId && item.relatedPlaceId === selectedPlace?.id).slice(0, 2),
    [activeEvents, selectedPlace?.id],
  );
  const searchCenter = themeDetail?.center ?? null;
  const bannerMessage = bootError ?? detailError ?? searchError;
  const isThemeReady = themeDetailState === "ready" && !!themeDetail;

  useEffect(() => {
    if (!selectedPlaceId) {
      return;
    }

    const selectedIndex = activePlaces.findIndex((place) => place.id === selectedPlaceId);
    if (selectedIndex >= 0 && selectedIndex >= placeListLimit) {
      setPlaceListLimit(Math.ceil((selectedIndex + 1) / INITIAL_PLACE_LIST_LIMIT) * INITIAL_PLACE_LIST_LIMIT);
    }
  }, [activePlaces, placeListLimit, selectedPlaceId]);

  useEffect(() => {
    if (!selectedPlaceId) {
      return;
    }

    const frameId = window.requestAnimationFrame(() => {
      resultItemRefs.current[selectedPlaceId]?.scrollIntoView({
        block: "nearest",
        behavior: "smooth",
      });
    });

    return () => window.cancelAnimationFrame(frameId);
  }, [placeListLimit, selectedPlaceId]);

  function handleSelectPlace(placeId: string) {
    setIsPanelOpen(true);
    setSelectedPlaceId(placeId);
  }

  async function handleSearchSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!activeThemeId || !themeDetail) {
      return;
    }

    const trimmedQuery = query.trim();
    if (!trimmedQuery) {
      setSearchResponse(null);
      setSearchState("idle");
      setSearchError(null);
      setSelectedPlaceId(null);
      setPlaceListLimit(INITIAL_PLACE_LIST_LIMIT);
      return;
    }

    setSearchState("loading");
    setSearchError(null);

    try {
      const payload: Record<string, unknown> = {
        query: trimmedQuery,
        themeId: activeThemeId,
        mode: "HYBRID",
        topK: 12,
      };

      if (activeTheme?.scope === "seoul") {
        payload.latitude = themeDetail.center.latitude;
        payload.longitude = themeDetail.center.longitude;
        payload.radiusKm = 12;
      }

      const result = await fetch("/api/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!result.ok) {
        throw new Error(`테마 검색 요청 실패 (${result.status})`);
      }

      const data = (await result.json()) as SearchResponse;
      setSearchResponse(data);
      setSelectedPlaceId(null);
      setSearchState("active");
      setPlaceListLimit(INITIAL_PLACE_LIST_LIMIT);
    } catch (error) {
      setSearchResponse(null);
      setSearchState("error");
      setSearchError(error instanceof Error ? error.message : "테마 검색에 실패했습니다.");
    }
  }

  function handleThemeClick(themeId: string) {
    setActiveThemeId(themeId);
    setSelectedPlaceId(null);
    setHoveredPlaceId(null);
    setIsPanelOpen(true);
    setPlaceListLimit(INITIAL_PLACE_LIST_LIMIT);
  }

  return (
    <main className={styles.page} data-panel-open={isPanelOpen}>
      <div className={styles.mapBackdrop}>
        <SearchMap
          results={activePlaces}
          selectedPlaceId={selectedPlaceId}
          hoveredPlaceId={hoveredPlaceId}
          comparedPlaceIds={[]}
          onSelectPlace={handleSelectPlace}
          searchCenter={searchCenter}
          radiusKm={activeTheme?.scope === "seoul" ? 12 : null}
          routeStops={[]}
          showClusters={activePlaces.length > 10}
          activeViewLabel={activeTheme?.title ?? "테마 지도"}
        />
      </div>

      <div className={styles.topBar}>
        {themes.map((theme) => {
          const active = theme.themeId === activeThemeId;
          return (
            <button
              key={theme.themeId}
              type="button"
              className={active ? styles.topChipActive : styles.topChip}
              onClick={() => handleThemeClick(theme.themeId)}
            >
              <strong>{theme.title}</strong>
            </button>
          );
        })}
      </div>

      <div className={styles.sidebarShell}>
        <div className={styles.iconRail}>
          <div className={styles.brandMark}>P</div>
          <button
            type="button"
            className={styles.railButton}
            onClick={() => setIsPanelOpen((current) => !current)}
            aria-label={isPanelOpen ? "패널 닫기" : "패널 열기"}
          >
            {isPanelOpen ? "←" : "→"}
          </button>
          <button
            type="button"
            className={styles.railButton}
            onClick={() => setSelectedPlaceId(null)}
            aria-label="전체 장소 보기"
          >
            ⌂
          </button>
        </div>

        <aside className={isPanelOpen ? styles.sidebar : styles.sidebarClosed}>
          <div className={styles.sidebarInner}>
            <div className={styles.sidebarHeader}>
              <span className={styles.sidebarEyebrow}>페로 테마맵</span>
              <h1>{activeTheme?.title ?? "테마를 불러오는 중"}</h1>
              <p>{activeTheme?.summary ?? "관광 테마를 고르면 지도와 장소가 함께 바뀝니다."}</p>
            </div>

            {bannerMessage ? <div className={styles.errorBanner}>{bannerMessage}</div> : null}

            <form className={styles.searchPanel} onSubmit={handleSearchSubmit}>
              <input
                className={styles.searchInput}
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="테마 안에서 다시 검색"
                aria-label="테마 안에서 다시 검색"
                disabled={!isThemeReady || searchState === "loading"}
              />
              <button className={styles.searchButton} type="submit" disabled={!isThemeReady || searchState === "loading"}>
                {searchState === "loading" ? "검색 중" : "검색"}
              </button>
            </form>

            <section className={styles.resultSection}>
              <div className={styles.sectionHeader}>
                <div>
                  <span className={styles.sectionLabel}>장소</span>
                  <strong>{searchState === "active" ? "검색 결과" : "추천 장소"}</strong>
                </div>
                <small>
                  {searchState === "active" && searchResponse
                    ? `${searchResponse.total}개 중 ${visiblePlaces.length}개`
                    : `${activePlaces.length}개 중 ${visiblePlaces.length}개`}
                </small>
              </div>

              {themeDetailState === "loading" ? <div className={styles.emptyState}>지도를 준비하는 중입니다.</div> : null}
              {themeDetailState === "ready" && visiblePlaces.length === 0 ? (
                <div className={styles.emptyState}>현재 조건에 맞는 장소가 없습니다.</div>
              ) : null}

              <div className={styles.resultList}>
                {visiblePlaces.map((place, index) => {
                  const rawPlace = placeRecords.get(place.id) ?? null;
                  const imageUrl = getRepresentativeImageUrl(rawPlace);
                  const active = selectedPlace?.id === place.id;

                  return (
                    <button
                      key={place.id}
                      type="button"
                      ref={(node) => {
                        resultItemRefs.current[place.id] = node;
                      }}
                      className={active ? styles.resultCardActive : styles.resultCard}
                      onClick={() => handleSelectPlace(place.id)}
                      onMouseEnter={() => setHoveredPlaceId(place.id)}
                      onMouseLeave={() => setHoveredPlaceId(null)}
                    >
                      {imageUrl ? (
                        <div className={styles.resultThumb} style={{ backgroundImage: `url(${imageUrl})` }} />
                      ) : (
                        <div className={styles.resultThumbFallback}>{String(index + 1).padStart(2, "0")}</div>
                      )}
                      <div className={styles.resultBody}>
                        <div className={styles.resultHead}>
                          <strong>{place.name}</strong>
                          <small>{place.category}</small>
                        </div>
                        <p>{place.district}</p>
                        <div className={styles.resultChips}>
                          {buildMetaChips(rawPlace).map((chip) => (
                            <span key={chip}>{chip}</span>
                          ))}
                        </div>
                      </div>
                    </button>
                  );
                })}
              </div>

              {visiblePlaces.length < activePlaces.length ? (
                <button
                  type="button"
                  className={styles.loadMoreButton}
                  onClick={() => setPlaceListLimit((current) => current + INITIAL_PLACE_LIST_LIMIT)}
                >
                  장소 더 보기
                </button>
              ) : null}
            </section>

            {selectedPlace ? (
              <section className={styles.selectionCard}>
                <div className={styles.sectionHeader}>
                  <div>
                    <span className={styles.sectionLabel}>선택 장소</span>
                    <strong>{selectedPlace.name}</strong>
                  </div>
                  <a
                    className={styles.outboundLink}
                    href={buildMapUrl(selectedPlace.latitude, selectedPlace.longitude)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    외부지도
                  </a>
                </div>

                {selectedImage ? (
                  <div className={styles.selectionImage} style={{ backgroundImage: `url(${selectedImage})` }} />
                ) : null}

                <p className={styles.selectionLead}>
                  {selectedPlaceLead(selectedPlace, "선택한 장소의 메타데이터와 설명을 지도 탐색용으로 정리했습니다.")}
                </p>

                <div className={styles.selectionMeta}>
                  {buildSelectionChips(selectedPlace).map((chip) => (
                    <span key={chip}>{chip}</span>
                  ))}
                </div>

                <p className={styles.selectionSummary}>
                  {sanitizeRichText(selectedPlace.tourApi?.common?.overview ?? selectedPlace.summary)}
                </p>

                {selectedEvents.length > 0 ? (
                  <div className={styles.inlineEvents}>
                    {selectedEvents.map((themeEvent: ThemeEvent) => (
                      <div key={themeEvent.id} className={styles.eventItem}>
                        <strong>{themeEvent.title}</strong>
                        <span>{themeEvent.periodLabel}</span>
                      </div>
                    ))}
                  </div>
                ) : null}
              </section>
            ) : null}
          </div>
        </aside>
      </div>

      {themeBootState === "loading" && themes.length === 0 ? <div className={styles.mapSkeleton}>테마를 불러오는 중입니다.</div> : null}
    </main>
  );
}

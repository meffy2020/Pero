"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import styles from "./page.module.css";
import type {
  PlaceResult,
  SearchMode,
  SearchResponse,
  SearchSourceMeta,
} from "./search-types";

const SearchMap = dynamic(
  () => import("./components/search-map").then((module) => module.SearchMap),
  {
    ssr: false,
    loading: () => <div className={styles.mapLoadingShell}>지도를 준비하는 중입니다.</div>,
  },
);

const DEFAULT_QUERY = "조용하게 오래 머물 수 있는 카페";

type ServiceLocation = {
  id: string;
  label: string;
  detail: string;
  latitude: string | null;
  longitude: string | null;
};

type SearchUiState = "idle" | "loading" | "success" | "error";

const serviceLocations: ServiceLocation[] = [
  {
    id: "all",
    label: "대한민국 전체",
    detail: "전국 기반 검색",
    latitude: null,
    longitude: null,
  },
  {
    id: "seoul",
    label: "서울",
    detail: "서울권 중심 검색",
    latitude: "37.5665",
    longitude: "126.978",
  },
  {
    id: "busan",
    label: "부산",
    detail: "부산권 중심 검색",
    latitude: "35.1796",
    longitude: "129.0756",
  },
  {
    id: "daegu",
    label: "대구",
    detail: "대구권 중심 검색",
    latitude: "35.8714",
    longitude: "128.6014",
  },
];

const radiusOptions = ["1", "3", "5", "8"];
const searchModes: { value: SearchMode; label: string; helper: string }[] = [
  { value: "HYBRID", label: "HYBRID", helper: "문맥+키워드+거리" },
  { value: "KEYWORD", label: "KEYWORD", helper: "명확한 단어 매칭" },
  { value: "VECTOR", label: "VECTOR", helper: "의도와 분위기 중심" },
];

const exampleQueries = [
  "집중해서 공부하기 좋은 카페",
  "아이와 함께 가기 편한 브런치",
  "반려동물과 들어갈 수 있는 카페",
];

function toNumberOrNull(value: string): number | null {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function getDistanceKm(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const r = 6_371;
  const toRad = (degree: number) => (degree * Math.PI) / 180;
  const deltaLat = toRad(bLat - aLat);
  const deltaLng = toRad(bLng - aLng);
  const latA = toRad(aLat);
  const latB = toRad(bLat);
  const haversine =
    Math.sin(deltaLat / 2) ** 2 + Math.cos(latA) * Math.cos(latB) * Math.sin(deltaLng / 2) ** 2;

  return 2 * r * Math.asin(Math.min(1, Math.sqrt(haversine)));
}

function buildRouteStops(places: PlaceResult[], anchorId: string | null, count = 4): PlaceResult[] {
  if (places.length < 2) {
    return places;
  }

  const ordered: PlaceResult[] = [];
  const start = places.find((place) => place.id === anchorId) ?? places[0];
  const remaining = places.filter((place) => place.id !== start.id);
  ordered.push(start);

  while (ordered.length < Math.min(count, places.length)) {
    const last = ordered[ordered.length - 1];
    let nearestIndex = 0;
    let nearestDistance = Number.POSITIVE_INFINITY;

    remaining.forEach((candidate, index) => {
      const candidateDistance = getDistanceKm(last.latitude, last.longitude, candidate.latitude, candidate.longitude);
      if (candidateDistance < nearestDistance) {
        nearestDistance = candidateDistance;
        nearestIndex = index;
      }
    });

    const nearest = remaining[nearestIndex];
    ordered.push(nearest);
    remaining.splice(nearestIndex, 1);
  }

  return ordered;
}

function getRouteLengthKm(stops: PlaceResult[]): number {
  if (stops.length < 2) {
    return 0;
  }

  let distance = 0;
  for (let index = 1; index < stops.length; index += 1) {
    const from = stops[index - 1];
    const to = stops[index];
    distance += getDistanceKm(from.latitude, from.longitude, to.latitude, to.longitude);
  }

  return distance;
}

function formatGeneratedAt(value: string | undefined | null): string {
  if (!value) {
    return "미입력";
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return value;
  }

  return parsed.toLocaleString("ko-KR");
}

function buildSourceBadges(source: SearchSourceMeta | undefined | null): string[] {
  if (!source) {
    return [];
  }

  return [
    `출처: ${source.providerName}`,
    `상태: ${source.status}`,
    `건수: ${source.count}건`,
    `갱신: ${formatGeneratedAt(source.generatedAt)}`,
  ];
}

export default function Home() {
  const defaultLocation = serviceLocations[0];

  const [query, setQuery] = useState(DEFAULT_QUERY);
  const [locationId, setLocationId] = useState(defaultLocation.id);
  const [latitude, setLatitude] = useState(defaultLocation.latitude ?? "");
  const [longitude, setLongitude] = useState(defaultLocation.longitude ?? "");
  const [locationLabel, setLocationLabel] = useState(
    `${defaultLocation.label} · ${defaultLocation.detail}`,
  );
  const [radiusKm, setRadiusKm] = useState("3");
  const [searchMode, setSearchMode] = useState<SearchMode>("HYBRID");
  const [response, setResponse] = useState<SearchResponse | null>(null);
  const [searchState, setSearchState] = useState<SearchUiState>("idle");
  const [locating, setLocating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedPlaceId, setSelectedPlaceId] = useState<string | null>(null);
  const [hoveredPlaceId, setHoveredPlaceId] = useState<string | null>(null);
  const [clusterMode, setClusterMode] = useState(false);
  const [routeMode, setRouteMode] = useState(false);
  const loading = searchState === "loading";

  const handleSelectPlace = useCallback((placeId: string) => {
    setSelectedPlaceId(placeId);
    setHoveredPlaceId(placeId);
  }, []);
  const handleHoverPlace = useCallback((placeId: string | null) => {
    setHoveredPlaceId(placeId);
  }, []);

  function applyLocation(location: ServiceLocation) {
    setLocationId(location.id);
    setLatitude(location.latitude ?? "");
    setLongitude(location.longitude ?? "");
    setLocationLabel(`${location.label} · ${location.detail}`);
  }

  const runSearch = useCallback(
    async (event?: FormEvent<HTMLFormElement>) => {
      event?.preventDefault();
      if (!query.trim()) {
        setError("검색어를 입력해 주세요.");
        setSearchState("error");
        setResponse(null);
        setSelectedPlaceId(null);
        return;
      }

      setSearchState("loading");
      setError(null);

      const hasLocation = latitude !== "" && longitude !== "";
      const payload = {
        query,
        mode: searchMode,
        latitude: hasLocation ? Number(latitude) : undefined,
        longitude: hasLocation ? Number(longitude) : undefined,
        radiusKm: hasLocation ? Number(radiusKm) : undefined,
        topK: 20,
      };

      try {
        const result = await fetch("/api/search", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });

        if (!result.ok) {
          const detail = await result.text();
          throw new Error(
            `검색 API 요청 실패 (${result.status})${detail ? `: ${detail}` : ""}`,
          );
        }

        const data = (await result.json()) as SearchResponse;
        setResponse(data);
        setSearchState("success");
        setSelectedPlaceId(data.results[0]?.id ?? null);
      } catch (searchError) {
        const message =
          searchError instanceof Error && searchError.message
            ? searchError.message
            : "서버 응답을 가져오지 못했습니다.";
        setError(message);
        setSearchState("error");
        setResponse(null);
        setSelectedPlaceId(null);
      }
    },
    [query, searchMode, latitude, longitude, radiusKm],
  );

  function requestCurrentLocation() {
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      setError("이 브라우저에서는 현재 위치를 가져올 수 없습니다.");
      return;
    }

    setLocating(true);
    setError(null);

    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLatitude(position.coords.latitude.toFixed(4));
        setLongitude(position.coords.longitude.toFixed(4));
        setLocationId("");
        setLocationLabel("현재 위치");
        setLocating(false);
      },
      () => {
        setError("위치 권한을 확인한 뒤 다시 시도해 주세요.");
        setLocating(false);
      },
      { enableHighAccuracy: true, timeout: 8000 },
    );
  }

  const mapCenter = useMemo(() => {
    const parsedLatitude = toNumberOrNull(latitude);
    const parsedLongitude = toNumberOrNull(longitude);

    if (parsedLatitude === null || parsedLongitude === null) {
      return null;
    }

    return { latitude: parsedLatitude, longitude: parsedLongitude };
  }, [latitude, longitude]);
  const radiusValue = useMemo(() => toNumberOrNull(radiusKm), [radiusKm]);
  const hasRadiusFilter = mapCenter !== null && radiusValue !== null && radiusValue > 0;

  const searchResults = useMemo(() => response?.results ?? [], [response]);
  const results = useMemo(() => {
    if (!hasRadiusFilter || !mapCenter) {
      return searchResults;
    }

    return searchResults.filter((place) => {
      const distance = getDistanceKm(
        mapCenter.latitude,
        mapCenter.longitude,
        place.latitude,
        place.longitude,
      );
      return distance <= radiusValue + 0.001;
    });
  }, [hasRadiusFilter, mapCenter, radiusValue, searchResults]);

  const selectedPlace = results.find((place) => place.id === selectedPlaceId) ?? results[0] ?? null;
  const routeStops = useMemo(
    () => buildRouteStops(results, selectedPlace?.id ?? null, 4),
    [results, selectedPlace],
  );
  const routeDistanceKm = useMemo(() => getRouteLengthKm(routeStops), [routeStops]);

  useEffect(() => {
    if (!results.length) {
      setSelectedPlaceId(null);
      return;
    }

    if (!selectedPlaceId || !results.some((place) => place.id === selectedPlaceId)) {
      setSelectedPlaceId(results[0].id);
    }
  }, [results, selectedPlaceId]);

  const sourceBadges = useMemo(
    () => buildSourceBadges(response?.source),
    [response?.source],
  );
  const searchResultSummary = useMemo(() => {
    if (searchState === "loading") {
      return "검색 중...";
    }
    if (searchState === "idle") {
      return "검색 실행 대기";
    }
    if (searchState === "error") {
      return error ?? "검색 오류";
    }
    if (!response) {
      return "조회 데이터 없음";
    }

    return hasRadiusFilter
      ? `반경 안 ${results.length}개 / 전체 ${searchResults.length}개`
      : `${results.length}개 결과`;
  }, [searchState, error, hasRadiusFilter, results.length, searchResults.length, response]);

  return (
    <div className={styles.page}>
      <form className={styles.topBar} onSubmit={runSearch}>
        <div className={styles.brandLine}>
          <strong className={styles.brandMark}>Pero</strong>
          <p className={styles.brandCopy}>메타데이터와 위치를 함께 읽는 장소 검색</p>
        </div>

        <div className={styles.searchRow}>
          <label className={styles.searchField}>
            <span className="sr-only">검색어</span>
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="예: 조용하게 오래 머물 수 있는 카페"
            />
          </label>
          <button type="submit" className={styles.searchButton} disabled={loading}>
            {loading ? "검색 중" : "검색"}
          </button>
          <button
            type="button"
            className={styles.locationButton}
            onClick={requestCurrentLocation}
            disabled={locating}
          >
            {locating ? "위치 가져오는 중" : "현재 위치 사용"}
          </button>
        </div>

        <div className={styles.quickRows}>
          {exampleQueries.map((item) => (
            <button
              key={item}
              type="button"
              className={styles.quickPill}
              onClick={() => setQuery(item)}
            >
              {item}
            </button>
            ))}
        </div>

        <div className={styles.statusLine}>
          <span>{searchMode}</span>
          <span>{radiusKm}km 반경</span>
          <span>{locationLabel}</span>
          <span>{searchResultSummary}</span>
          <span>{clusterMode ? "클러스터 ON" : "클러스터 OFF"}</span>
          <span>{routeMode ? "경로 ON" : "경로 OFF"}</span>
        </div>
      </form>

      <main className={styles.workspace}>
        <SearchMap
          results={results}
          selectedPlaceId={selectedPlaceId}
          hoveredPlaceId={hoveredPlaceId}
          onSelectPlace={handleSelectPlace}
          onHoverPlace={handleHoverPlace}
          searchCenter={mapCenter}
          radiusKm={hasRadiusFilter ? radiusValue : null}
          clusterMode={clusterMode}
          routeModeEnabled={routeMode}
          routeStops={routeMode ? routeStops : null}
          routeLengthKm={routeMode ? routeDistanceKm : null}
        />

        <section className={styles.resultsPanel}>
          <header className={styles.panelHeader}>
            <h1>검색 결과</h1>
            <p>지도 위 결과와 동일한 근거를 함께 확인하세요.</p>
          </header>

          <div className={styles.panelControls}>
            <label>
              <span>지역</span>
              <select
                value={locationId}
                onChange={(event) => {
                  const location = serviceLocations.find(
                    (item) => item.id === event.target.value,
                  );
                  if (location) {
                    applyLocation(location);
                  }
                }}
              >
                {serviceLocations.map((location) => (
                  <option key={location.id} value={location.id}>
                    {location.label}
                  </option>
                ))}
              </select>
            </label>

            <label>
              <span>반경</span>
              <select value={radiusKm} onChange={(event) => setRadiusKm(event.target.value)}>
                {radiusOptions.map((option) => (
                  <option key={option} value={option}>
                    {option}km
                  </option>
                ))}
              </select>
            </label>

            <label>
              <span>방식</span>
              <select
                value={searchMode}
                onChange={(event) => setSearchMode(event.target.value as SearchMode)}
              >
                {searchModes.map((mode) => (
                  <option key={mode.value} value={mode.value}>
                    {mode.label}
                  </option>
                ))}
              </select>
            </label>

            <button type="button" onClick={requestCurrentLocation} disabled={locating}>
              {locating ? "위치 확인 중" : "현재 위치"}
            </button>
          </div>

          <p className={styles.helperRow}>
            {searchModes.find((mode) => mode.value === searchMode)?.helper}
          </p>

          <div className={styles.metaBadgeRow}>
            {sourceBadges.map((badge) => (
              <span key={badge} className={styles.badgeMuted}>
                {badge}
              </span>
            ))}
            {searchState !== "idle" && searchState !== "loading" ? (
              <span className={styles.badgeMuted}>
                응답시간: {formatGeneratedAt(response?.source?.generatedAt ?? response?.generatedAt)}
              </span>
            ) : null}
          </div>

          <div className={styles.panelToggleRow}>
            <label className={styles.togglePill}>
              <input
                type="checkbox"
                checked={clusterMode}
                onChange={(event) => setClusterMode(event.target.checked)}
              />
              <span>클러스터 레이어</span>
            </label>
            <label className={styles.togglePill}>
              <input
                type="checkbox"
                checked={routeMode}
                onChange={(event) => setRouteMode(event.target.checked)}
              />
              <span>추천 경로 모드</span>
            </label>
          </div>

          {routeMode && routeStops.length > 1 ? (
            <p className={styles.routeInfo}>
              추천 경로: {routeStops.length}개 정거장 · 총거리 {routeDistanceKm.toFixed(2)}km
            </p>
          ) : null}

          {error ? <p className={styles.errorMessage}>{error}</p> : null}

          <div className={styles.resultList}>
            {searchState === "loading" ? (
              <div className={styles.emptyState}>
                <strong>검색 중입니다.</strong>
                <p>잠시만 기다려 주세요. 결과가 준비되면 패널이 갱신됩니다.</p>
              </div>
            ) : null}
            {searchState === "idle" ? (
              <div className={styles.emptyState}>
                <strong>검색을 시작하세요.</strong>
                <p>상단 검색창에서 질의 후 {`"`}검색{`"`}을 눌러 결과를 받아주세요.</p>
              </div>
            ) : null}
            {searchState === "error" ? (
              <div className={styles.emptyState}>
                <strong>검색 요청 실패</strong>
                <p>백엔드 응답을 다시 확인해 주세요. 검색어/필터를 바꾸어 재시도할 수 있습니다.</p>
              </div>
            ) : null}
            {searchState === "success" && results.length === 0 ? (
              <div className={styles.emptyState}>
                <strong>일치하는 장소가 없습니다.</strong>
                <p>검색어를 바꾸거나 반경을 넓혀 다시 시도해 보세요.</p>
              </div>
            ) : null}
            {searchState === "success" && results.length ? (
              results.map((place, index) => (
                <ResultCard
                  key={place.id}
                  index={index}
                  place={place}
                  active={place.id === selectedPlaceId}
                  isHovered={place.id === hoveredPlaceId}
                  onSelect={() => setSelectedPlaceId(place.id)}
                  onHover={(placeId) => setHoveredPlaceId(placeId)}
                />
              ))
            ) : null}
          </div>
        </section>

        {selectedPlace ? (
          <SelectedEvidencePanel place={selectedPlace} mode={response?.mode ?? searchMode} />
        ) : null}
      </main>
    </div>
  );
}

function SelectedEvidencePanel({
  place,
  mode,
}: {
  place: PlaceResult;
  mode: SearchMode;
}) {
  const scores = [
    { label: "키워드", value: place.keywordScore },
    { label: "문맥", value: place.vectorScore },
    { label: "특징", value: place.featureScore },
    { label: "위치", value: place.geoScore },
  ];

  return (
    <aside className={styles.evidencePanel} aria-label={`${place.name} 검색 근거`}>
      <div className={styles.evidencePanelHeader}>
        <span className={styles.badge}>{mode} 선택됨</span>
        <h2>{place.name}</h2>
        <p>
          {place.category} · {place.district} · {place.roadAddress}
        </p>
      </div>

      <div className={styles.metaGrid}>
        <div>
          <span>좌표</span>
          <strong>{place.latitude.toFixed(4)}</strong>
          <strong>{place.longitude.toFixed(4)}</strong>
        </div>
        <div>
          <span>거리</span>
          <strong>{place.distanceKm == null ? "없음" : `${place.distanceKm.toFixed(2)} km`}</strong>
        </div>
        <div>
          <span>종합 점수</span>
          <strong>{Math.round(place.finalScore * 100)}</strong>
        </div>
      </div>

      <div className={styles.reasonBlock}>
        <span>선택 장소 근거</span>
        <p>{place.evidence}</p>
      </div>

      <div className={styles.scoreGrid} aria-label="검색 점수 구성">
        {scores.map((score) => (
          <div className={styles.scoreItem} key={score.label}>
            <span>{score.label}</span>
            <strong>{Math.round(score.value * 100)}</strong>
          </div>
        ))}
      </div>

      <div className={styles.tagCloud}>
        {place.tags.slice(0, 4).map((tag) => (
          <span key={`${place.id}-evidence-${tag}`}>{tag}</span>
        ))}
      </div>
    </aside>
  );
}

function ResultCard({
  index,
  place,
  active,
  onSelect,
  onHover,
  isHovered,
}: {
  index: number;
  place: PlaceResult;
  active: boolean;
  isHovered: boolean;
  onSelect: () => void;
  onHover: (placeId: string | null) => void;
}) {
  const mapUrl = buildMapUrl(place.latitude, place.longitude);

  return (
    <article
      className={`${styles.resultCard} ${active ? styles.resultCardActive : ""} ${isHovered ? styles.resultCardHover : ""}`}
      onMouseEnter={() => onHover(place.id)}
      onMouseLeave={() => onHover(null)}
      onClick={onSelect}
      tabIndex={0}
      role="button"
      onFocus={() => onHover(place.id)}
      onBlur={() => onHover(null)}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          onSelect();
        }
      }}
    >
      <div className={styles.resultRow}>
        <h3>{place.name}</h3>
        <p className={styles.coordinate}>
          {place.latitude.toFixed(4)}° N, {place.longitude.toFixed(4)}° E
        </p>
      </div>

      <p className={styles.summary}>{place.summary}</p>

      <p className={styles.distance}>
        {place.distanceKm !== null ? `${place.distanceKm.toFixed(2)} km` : "거리 정보 없음"}
      </p>

      <p className={styles.evidenceText}>{place.evidence}</p>

      <div className={styles.cardActions}>
        <a
          href={mapUrl}
          target="_blank"
          rel="noreferrer"
          onClick={(event) => event.stopPropagation()}
        >
          길찾기
        </a>
        <span>#{String(index + 1).padStart(2, "0")}</span>
      </div>
    </article>
  );
}

function buildMapUrl(latitude: number, longitude: number) {
  return `https://www.google.com/maps/search/?api=1&query=${latitude},${longitude}`;
}

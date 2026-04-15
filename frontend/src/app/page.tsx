"use client";

import { startTransition, useEffect, useState } from "react";
import type { FormEvent } from "react";
import { SearchMap } from "./components/search-map";
import type {
  PlaceResult,
  SearchResponse,
  SearchMode,
} from "./search-types";

const DEFAULT_QUERY = "조용하게 오래 머물 수 있는 카페";

type ServiceLocation = {
  id: string;
  label: string;
  detail: string;
  latitude: string | null;
  longitude: string | null;
};

const serviceLocations: ServiceLocation[] = [
  {
    id: "all",
    label: "전체 지역",
    detail: "위치 필터 없이 전체 데이터 검색",
    latitude: null,
    longitude: null,
  },
  {
    id: "hongdae",
    label: "홍대입구",
    detail: "연남동, 서교동, 합정 인근",
    latitude: "37.5535",
    longitude: "126.9221",
  },
  {
    id: "seongsu",
    label: "성수",
    detail: "서울숲, 성수 카페거리 인근",
    latitude: "37.5448",
    longitude: "127.0557",
  },
  {
    id: "jamsil",
    label: "잠실",
    detail: "석촌호수, 송리단길 인근",
    latitude: "37.5131",
    longitude: "127.1025",
  },
  {
    id: "yeonnam",
    label: "연남",
    detail: "연트럴파크 주변",
    latitude: "37.5628",
    longitude: "126.9258",
  },
  {
    id: "seochon",
    label: "서촌",
    detail: "경복궁 주변",
    latitude: "37.5787",
    longitude: "126.9692",
  },
];

const radiusOptions = ["1", "3", "5", "8"];
const searchModes: { value: SearchMode; label: string; helper: string }[] = [
  { value: "HYBRID", label: "HYBRID", helper: "문맥+키워드+거리" },
  { value: "KEYWORD", label: "KEYWORD", helper: "명확한 단어 매칭" },
  { value: "VECTOR", label: "VECTOR", helper: "분위기와 의도 중심" },
];
const exampleQueries = [
  "집중해서 공부하기 좋은 카페",
  "아이와 함께 가기 편한 브런치",
  "반려동물과 들어갈 수 있는 카페",
];

const demoResults: PlaceResult[] = [
  {
    id: "demo-01",
    name: "Archive Coffee Roasters",
    category: "카페",
    district: "마포구 연남동",
    address: "서울 마포구 연남동 240-14",
    roadAddress: "서울 마포구 동교로38길 27",
    summary: "긴 체류와 조용한 작업에 맞춘 좌석 구성이 강한 카페입니다.",
    tags: ["quiet", "work", "coffee", "wifi"],
    latitude: 37.5628,
    longitude: 126.9258,
    distanceKm: 0.86,
    evidence: "조용함, 콘센트, 장시간 체류 태그가 검색 의도와 직접 매칭되고 현재 홍대입구 기준 접근성이 높습니다.",
    keywordScore: 0.88,
    vectorScore: 0.91,
    featureScore: 0.86,
    geoScore: 0.82,
    finalScore: 0.89,
  },
  {
    id: "demo-02",
    name: "Paper Ground",
    category: "북카페",
    district: "마포구 서교동",
    address: "서울 마포구 서교동 395-121",
    roadAddress: "서울 마포구 와우산로29길 16",
    summary: "책장과 분리 좌석이 있어 혼자 머무르는 검색 의도에 잘 맞습니다.",
    tags: ["book", "solo", "calm", "seat"],
    latitude: 37.5552,
    longitude: 126.9295,
    distanceKm: 0.74,
    evidence: "북카페, 혼자 방문, 낮은 소음 메타데이터가 벡터 검색에서 높은 유사도를 만들었습니다.",
    keywordScore: 0.76,
    vectorScore: 0.94,
    featureScore: 0.81,
    geoScore: 0.87,
    finalScore: 0.86,
  },
  {
    id: "demo-03",
    name: "Lowkey Table",
    category: "브런치",
    district: "마포구 동교동",
    address: "서울 마포구 동교동 153-3",
    roadAddress: "서울 마포구 월드컵북로4길 22",
    summary: "브런치와 커피를 함께 해결할 수 있는 조용한 낮 시간대 후보입니다.",
    tags: ["brunch", "daytime", "table", "nearby"],
    latitude: 37.5586,
    longitude: 126.9211,
    distanceKm: 0.48,
    evidence: "식사 가능, 낮 시간, 가까운 거리 조건이 함께 반영되어 하이브리드 랭킹 상위에 배치됐습니다.",
    keywordScore: 0.71,
    vectorScore: 0.83,
    featureScore: 0.88,
    geoScore: 0.93,
    finalScore: 0.84,
  },
  {
    id: "demo-04",
    name: "Stationary Room",
    category: "복합문화공간",
    district: "마포구 합정동",
    address: "서울 마포구 합정동 412-1",
    roadAddress: "서울 마포구 독막로7길 44",
    summary: "문구, 책, 전시 분위기가 섞여 있어 목적 없는 탐색에 적합합니다.",
    tags: ["culture", "stationary", "gallery", "walk"],
    latitude: 37.5489,
    longitude: 126.9187,
    distanceKm: 1.22,
    evidence: "장소 설명의 문화공간 문맥과 산책/탐색 의도가 강하게 연결되어 추천 후보로 유지됐습니다.",
    keywordScore: 0.68,
    vectorScore: 0.89,
    featureScore: 0.79,
    geoScore: 0.74,
    finalScore: 0.79,
  },
];

function buildDemoResponse(query: string, mode: SearchMode): SearchResponse {
  return {
    query,
    mode,
    total: demoResults.length,
    topK: demoResults.length,
    generatedAt: new Date().toISOString(),
    results: demoResults,
  };
}

function buildEmptyResponse(query: string, mode: SearchMode): SearchResponse {
  return {
    query,
    mode,
    total: 0,
    topK: 20,
    generatedAt: new Date().toISOString(),
    results: [],
  };
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
  const [response, setResponse] = useState<SearchResponse>(() =>
    buildEmptyResponse(DEFAULT_QUERY, "HYBRID"),
  );
  const [loading, setLoading] = useState(false);
  const [locating, setLocating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedPlaceId, setSelectedPlaceId] = useState<string | null>(
    null,
  );
  const [showSearchPanels, setShowSearchPanels] = useState(false);

  function applyLocation(location: ServiceLocation) {
    setLocationId(location.id);
    setLatitude(location.latitude ?? "");
    setLongitude(location.longitude ?? "");
    setLocationLabel(`${location.label} · ${location.detail}`);
  }

  async function runSearch(event?: FormEvent<HTMLFormElement>) {
    event?.preventDefault();
    setLoading(true);
    setError(null);
    setShowSearchPanels(true);
    const hasLocation = latitude !== "" && longitude !== "";

    try {
      const result = await fetch("/api/search", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          query,
          mode: searchMode,
          latitude: hasLocation ? Number(latitude) : undefined,
          longitude: hasLocation ? Number(longitude) : undefined,
          radiusKm: hasLocation ? Number(radiusKm) : undefined,
          topK: 20,
        }),
      });

      if (!result.ok) {
        const message = await result.text();
        throw new Error(message || "검색 요청에 실패했습니다.");
      }

      const data = (await result.json()) as SearchResponse;
      startTransition(() => {
        setResponse(data);
        setSelectedPlaceId(data.results[0]?.id ?? null);
      });
    } catch {
      startTransition(() => {
        setResponse(buildDemoResponse(query, searchMode));
        setSelectedPlaceId(demoResults[0].id);
      });
      setError(null);
    } finally {
      setLoading(false);
    }
  }

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
      {
        enableHighAccuracy: true,
        timeout: 8000,
      },
    );
  }

  const results = response.results;

  function openSearchPanels() {
    setShowSearchPanels(true);
  }

  function selectPlace(placeId: string) {
    openSearchPanels();
    setSelectedPlaceId(placeId);
  }

  useEffect(() => {
    if (!results.length) {
      setSelectedPlaceId(null);
      return;
    }

    if (!selectedPlaceId) {
      setSelectedPlaceId(results[0].id);
      return;
    }

    if (!results.some((place) => place.id === selectedPlaceId)) {
      setSelectedPlaceId(results[0].id);
    }
  }, [results, selectedPlaceId]);

  const selectedPlace =
    results.find((place) => place.id === selectedPlaceId) ?? results[0] ?? null;

  return (
    <div className="precision-shell">
      <nav className="top-nav">
        <div className="brand-group">
          <strong className="brand-mark">Pero</strong>
          <div className="top-tabs">
            <a className="active" href="#results">Explore</a>
            <a href="#saved">Saved</a>
            <a href="#analytics">Analytics</a>
          </div>
        </div>

        <form className="top-search" onSubmit={runSearch}>
          <span aria-hidden="true">⌕</span>
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search coordinates or landmarks..."
          />
          <button type="submit" disabled={loading}>
            {loading ? "Searching" : "Search"}
          </button>
        </form>

        <div className="nav-icons" aria-label="account actions">
          <button type="button">●</button>
          <button type="button">◎</button>
        </div>
      </nav>

      <div className="workspace">
        {showSearchPanels ? (
          <aside className="side-nav">
          <div className="side-title">
            <span>Navigation</span>
            <strong>Precision Search</strong>
          </div>

          <nav>
            <a className="active" href="#map">Map View</a>
            <a href="#results">List View</a>
            <a href="#coordinates">Coordinates</a>
            <a href="#deep-search">Deep Search</a>
            <a href="#filtered">Filtered</a>
          </nav>

            <button className="new-search" type="button" onClick={() => void runSearch()}>
              New Search
            </button>
          </aside>
        ) : null}

          <main
            className={`precision-main ${showSearchPanels ? "precision-main--with-panels" : ""}`}
            id="map-main"
          >
            {showSearchPanels ? (
              <section className="result-rail" id="results">
                <header className="results-header">
                  <h1>Search Results</h1>
                  <p>
                    Found {results.length} contextual nodes near {locationLabel}
                  </p>
                </header>

                <div className="control-strip" id="deep-search">
                  <label>
                    <span>Area</span>
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
                    <span>Radius</span>
                    <select value={radiusKm} onChange={(event) => setRadiusKm(event.target.value)}>
                      {radiusOptions.map((option) => (
                        <option key={option} value={option}>
                          {option}km
                        </option>
                      ))}
                    </select>
                  </label>

                  <label>
                    <span>Mode</span>
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
                    {locating ? "Locating" : "Use Location"}
                  </button>
                </div>

                <div className="example-row">
                  {exampleQueries.map((item) => (
                    <button key={item} type="button" onClick={() => setQuery(item)}>
                      {item}
                    </button>
                  ))}
                </div>

                {error ? <p className="status-box">{error}</p> : null}

                <div className="result-list">
                  {results.length ? (
                    results.map((place, index) => (
                      <ResultCard
                        key={place.id}
                        index={index}
                        place={place}
                        active={place.id === selectedPlaceId}
                        onSelect={() => selectPlace(place.id)}
                      />
                    ))
                  ) : (
                    <div className="empty-state">
                      <strong>{loading ? "Searching nodes..." : "No matching nodes."}</strong>
                      <p>검색어를 바꾸거나 반경을 넓혀 다시 시도해 보세요.</p>
                    </div>
                  )}
                </div>
              </section>
            ) : null}

            <section className="map-stage" id="map">
              <SearchMap
                results={results ?? []}
                selectedPlaceId={selectedPlaceId}
                onSelectPlace={selectPlace}
              />

              {selectedPlace ? (
                <SelectedEvidencePanel place={selectedPlace} mode={response?.mode ?? searchMode} />
              ) : (
                <div className="map-status-card">
                  <span>Reference System</span>
                  <strong>WGS84_PROJECTION</strong>
                </div>
              )}
            </section>
        </main>
      </div>
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
    <aside className="evidence-panel" aria-label={`${place.name} 검색 근거`}>
      <div className="evidence-panel-header">
        <span className="rank-badge">{mode} Evidence Open</span>
        <h3>{place.name}</h3>
        <p>{place.category} · {place.district} · {place.roadAddress}</p>
      </div>

      <div className="evidence-meta-grid">
        <div>
          <span>Coordinates</span>
          <strong>{place.latitude.toFixed(4)} / {place.longitude.toFixed(4)}</strong>
        </div>
        <div>
          <span>Distance</span>
          <strong>{place.distanceKm == null ? "N/A" : `${place.distanceKm.toFixed(2)} KM`}</strong>
        </div>
        <div>
          <span>Final Score</span>
          <strong>{Math.round(place.finalScore * 100)}</strong>
        </div>
      </div>

      <div className="reason-block">
        <span>선택 장소 근거</span>
        <blockquote>{place.evidence}</blockquote>
      </div>

      <div className="score-grid" aria-label="검색 점수 구성">
        {scores.map((score) => (
          <div className="score-item" key={score.label}>
            <span>{score.label}</span>
            <strong>{Math.round(score.value * 100)}</strong>
          </div>
        ))}
      </div>

      <div className="evidence-tags">
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
}: {
  index: number;
  place: PlaceResult;
  active: boolean;
  onSelect: () => void;
}) {
  const mapUrl = buildMapUrl(place.latitude, place.longitude);

  return (
    <article
      className={active ? "result-card active" : "result-card"}
      onClick={onSelect}
    >
      <div className="result-meta-row">
        <h3>{place.name}</h3>
        <span className="coordinate">
          {place.latitude.toFixed(4)}° N, {place.longitude.toFixed(4)}° E
        </span>
      </div>

      <div className="place-preview" aria-hidden="true">
        <span>{String(index + 1).padStart(2, "0")}</span>
      </div>

      <div className="result-distance-row">
        {place.distanceKm !== null ? (
          <span>{place.distanceKm.toFixed(2)} KM Distance</span>
        ) : null}
      </div>

      <div className="reason-block">
        <span>검색 근거</span>
        <blockquote>{place.evidence}</blockquote>
      </div>

      <div className="card-actions">
        <button className="text-action" type="button">View Evidence</button>
        <a
          className="text-action"
          href={mapUrl}
          target="_blank"
          rel="noreferrer"
          onClick={(event) => event.stopPropagation()}
        >
          길찾기
        </a>
      </div>
    </article>
  );
}

function buildMapUrl(latitude: number, longitude: number) {
  return `https://www.google.com/maps/search/?api=1&query=${latitude},${longitude}`;
}

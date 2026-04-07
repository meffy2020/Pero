"use client";

import { startTransition, useEffect, useEffectEvent, useState } from "react";
import type { FormEvent } from "react";
import { SearchMap } from "./components/search-map";
import type { PlaceResult, SearchMode, SearchResponse } from "./search-types";

const ALL_FILTER = "ALL";

const modeLabels: Record<SearchMode, string> = {
  KEYWORD: "Keyword",
  VECTOR: "Vector",
  HYBRID: "Hybrid",
};

const presets = [
  { label: "홍대", latitude: "37.5535", longitude: "126.9221" },
  { label: "성수", latitude: "37.5448", longitude: "127.0557" },
  { label: "잠실", latitude: "37.5131", longitude: "127.1025" },
];

const quickQueries = [
  "조용하게 공부하기 좋은 카페",
  "아이와 함께 가기 좋은 브런치",
  "반려동물과 갈 수 있는 카페",
  "분위기 좋은 디저트 카페",
];

export default function Home() {
  const [query, setQuery] = useState("조용하게 공부하기 좋은 카페");
  const [mode, setMode] = useState<SearchMode>("HYBRID");
  const [latitude, setLatitude] = useState(presets[0].latitude);
  const [longitude, setLongitude] = useState(presets[0].longitude);
  const [radiusKm, setRadiusKm] = useState("6");
  const [response, setResponse] = useState<SearchResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedPlaceId, setSelectedPlaceId] = useState<string | null>(null);
  const [categoryFilter, setCategoryFilter] = useState(ALL_FILTER);
  const [tagFilter, setTagFilter] = useState(ALL_FILTER);

  async function runSearch(event?: FormEvent<HTMLFormElement>) {
    event?.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const payload = {
        query,
        mode,
        latitude: Number(latitude),
        longitude: Number(longitude),
        radiusKm: Number(radiusKm),
        topK: 6,
      };

      const result = await fetch("/api/search", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      if (!result.ok) {
        const message = await result.text();
        throw new Error(message || "검색 요청에 실패했습니다.");
      }

      const data = (await result.json()) as SearchResponse;
      startTransition(() => {
        setResponse(data);
        setSelectedPlaceId(data.results[0]?.id ?? null);
        setCategoryFilter(ALL_FILTER);
        setTagFilter(ALL_FILTER);
      });
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "알 수 없는 오류가 발생했습니다.",
      );
    } finally {
      setLoading(false);
    }
  }

  const runInitialSearch = useEffectEvent(() => {
    void runSearch();
  });

  useEffect(() => {
    runInitialSearch();
  }, []);

  const allResults = response?.results ?? [];
  const categoryOptions = [
    ALL_FILTER,
    ...Array.from(new Set(allResults.map((place) => place.category))),
  ];
  const tagOptions = [
    ALL_FILTER,
    ...Array.from(new Set(allResults.flatMap((place) => place.tags))),
  ].slice(0, 10);

  const filteredResults = allResults.filter((place) => {
    const matchesCategory =
      categoryFilter === ALL_FILTER || place.category === categoryFilter;
    const matchesTag = tagFilter === ALL_FILTER || place.tags.includes(tagFilter);
    return matchesCategory && matchesTag;
  });

  useEffect(() => {
    if (!filteredResults.length) {
      if (selectedPlaceId !== null) {
        setSelectedPlaceId(null);
      }
      return;
    }

    if (!selectedPlaceId) {
      setSelectedPlaceId(filteredResults[0].id);
      return;
    }

    const selectedStillVisible = filteredResults.some(
      (place) => place.id === selectedPlaceId,
    );

    if (!selectedStillVisible) {
      setSelectedPlaceId(filteredResults[0].id);
    }
  }, [filteredResults, selectedPlaceId]);

  return (
    <main className="app-shell">
      <section className="hero-panel">
        <div className="hero-copy">
          <span className="eyebrow">Geo-Semantic Search Prototype</span>
          <h1>Lumo</h1>
          <p className="hero-text">
            Spring Boot 기반 장소 검색 프로토타입입니다. 이제 실제 지도를 붙여
            검색 결과와 마커를 함께 비교할 수 있게 구성했습니다.
          </p>
        </div>

        <div className="hero-metrics">
          <MetricCard
            label="Backend"
            value="Spring Boot"
            detail="BM25-lite + hashed vector + fusion"
          />
          <MetricCard
            label="Frontend"
            value="Next.js"
            detail="실제 지도와 결과 상호작용이 가능한 UI"
          />
          <MetricCard
            label="Dataset"
            value={`${filteredResults.length} shown`}
            detail={`${response?.total ?? 0}개 결과 중 필터 적용`}
          />
        </div>
      </section>

      <section className="workspace">
        <form className="control-panel" onSubmit={runSearch}>
          <div className="panel-header">
            <h2>Search Lab</h2>
            <p>질의 문장과 위치를 바꿔보면서 결과와 지도 반응을 함께 보세요.</p>
          </div>

          <label className="field">
            <span>Query</span>
            <textarea
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              rows={3}
              placeholder="예: 조용하게 공부하기 좋은 카페"
            />
          </label>

          <div className="chip-group">
            {quickQueries.map((item) => (
              <button
                key={item}
                className="ghost-chip"
                type="button"
                onClick={() => setQuery(item)}
              >
                {item}
              </button>
            ))}
          </div>

          <div className="mode-grid">
            {(["KEYWORD", "VECTOR", "HYBRID"] as const).map((item) => (
              <button
                key={item}
                type="button"
                className={item === mode ? "mode-chip active" : "mode-chip"}
                onClick={() => setMode(item)}
              >
                <strong>{modeLabels[item]}</strong>
                <span>
                  {item === "KEYWORD" && "명시적 키워드와 카테고리 매칭"}
                  {item === "VECTOR" && "확장 토큰과 벡터 유사도 중심"}
                  {item === "HYBRID" && "두 검색 결과를 융합한 실험 모드"}
                </span>
              </button>
            ))}
          </div>

          <div className="location-row">
            <div className="field compact">
              <span>Latitude</span>
              <input
                value={latitude}
                onChange={(event) => setLatitude(event.target.value)}
                inputMode="decimal"
              />
            </div>
            <div className="field compact">
              <span>Longitude</span>
              <input
                value={longitude}
                onChange={(event) => setLongitude(event.target.value)}
                inputMode="decimal"
              />
            </div>
            <div className="field compact">
              <span>Radius (km)</span>
              <input
                value={radiusKm}
                onChange={(event) => setRadiusKm(event.target.value)}
                inputMode="decimal"
              />
            </div>
          </div>

          <div className="chip-group">
            {presets.map((preset) => (
              <button
                key={preset.label}
                type="button"
                className="ghost-chip"
                onClick={() => {
                  setLatitude(preset.latitude);
                  setLongitude(preset.longitude);
                }}
              >
                {preset.label}
              </button>
            ))}
          </div>

          <button className="submit-button" type="submit" disabled={loading}>
            {loading ? "검색 중..." : "실험 실행"}
          </button>

          {error ? <p className="error-box">{error}</p> : null}
        </form>

        <section className="result-panel">
          <div className="result-header">
            <div>
              <h2>Search Result</h2>
              <p>
                {response
                  ? `"${response.query}"에 대한 ${filteredResults.length} / ${response.total}개 결과`
                  : "검색 결과가 여기에 표시됩니다."}
              </p>
            </div>
            {response ? (
              <div className="result-meta">
                <span>{modeLabels[response.mode]}</span>
                <span>{new Date(response.generatedAt).toLocaleTimeString()}</span>
              </div>
            ) : null}
          </div>

          <section className="filter-panel">
            <div className="filter-group">
              <span className="filter-label">Category</span>
              <div className="chip-group">
                {categoryOptions.map((option) => (
                  <button
                    key={option}
                    type="button"
                    className={
                      option === categoryFilter ? "filter-chip active" : "filter-chip"
                    }
                    onClick={() => setCategoryFilter(option)}
                  >
                    {option === ALL_FILTER ? "전체" : option}
                  </button>
                ))}
              </div>
            </div>

            <div className="filter-group">
              <span className="filter-label">Tag</span>
              <div className="chip-group">
                {tagOptions.map((option) => (
                  <button
                    key={option}
                    type="button"
                    className={
                      option === tagFilter ? "filter-chip active" : "filter-chip"
                    }
                    onClick={() => setTagFilter(option)}
                  >
                    {option === ALL_FILTER ? "전체" : option}
                  </button>
                ))}
              </div>
            </div>
          </section>

          <SearchMap
            results={filteredResults}
            selectedPlaceId={selectedPlaceId}
            onSelectPlace={setSelectedPlaceId}
          />

          <div className="result-list">
            {filteredResults.length ? (
              filteredResults.map((place, index) => (
                <ResultCard
                  key={place.id}
                  index={index}
                  place={place}
                  active={place.id === selectedPlaceId}
                  onSelect={() => setSelectedPlaceId(place.id)}
                />
              ))
            ) : (
              <div className="empty-state">
                <p>검색 결과가 없습니다. 필터를 해제하거나 질의를 바꿔보세요.</p>
              </div>
            )}
          </div>
        </section>
      </section>
    </main>
  );
}

function MetricCard({
  label,
  value,
  detail,
}: {
  label: string;
  value: string;
  detail: string;
}) {
  return (
    <article className="metric-card">
      <span>{label}</span>
      <strong>{value}</strong>
      <p>{detail}</p>
    </article>
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
  return (
    <article
      className={active ? "result-card active" : "result-card"}
      onClick={onSelect}
    >
      <div className="result-topline">
        <span className="rank-badge">#{index + 1}</span>
        <span className="result-score">final {place.finalScore.toFixed(3)}</span>
      </div>

      <div className="result-heading">
        <div>
          <h3>{place.name}</h3>
          <p>
            {place.category} · {place.district}
          </p>
        </div>
        {place.distanceKm !== null ? (
          <span className="distance-pill">{place.distanceKm.toFixed(2)}km</span>
        ) : null}
      </div>

      <p className="summary">{place.summary}</p>

      <div className="tag-row">
        {place.tags.map((tag) => (
          <span className="tag" key={`${place.id}-${tag}`}>
            {tag}
          </span>
        ))}
      </div>

      <div className="score-grid">
        <ScoreBadge label="Keyword" value={place.keywordScore} />
        <ScoreBadge label="Vector" value={place.vectorScore} />
        <ScoreBadge label="Feature" value={place.featureScore} />
        <ScoreBadge label="Geo" value={place.geoScore} />
      </div>

      <blockquote>{place.evidence}</blockquote>
    </article>
  );
}

function ScoreBadge({ label, value }: { label: string; value: number }) {
  return (
    <div className="score-badge">
      <span>{label}</span>
      <strong>{value.toFixed(3)}</strong>
    </div>
  );
}

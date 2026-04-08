"use client";

import { startTransition, useEffect, useEffectEvent, useState } from "react";
import type { FormEvent } from "react";
import { SearchMap } from "./components/search-map";
import type { PlaceResult, SearchResponse } from "./search-types";

const DEFAULT_QUERY = "조용하게 오래 머물 수 있는 카페";

type ServiceLocation = {
  id: string;
  label: string;
  detail: string;
  latitude: string;
  longitude: string;
};

const serviceLocations: ServiceLocation[] = [
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
const exampleQueries = [
  "집중해서 공부하기 좋은 카페",
  "아이와 함께 가기 편한 브런치",
  "반려동물과 들어갈 수 있는 카페",
];

export default function Home() {
  const defaultLocation = serviceLocations[0];

  const [query, setQuery] = useState(DEFAULT_QUERY);
  const [locationId, setLocationId] = useState(defaultLocation.id);
  const [latitude, setLatitude] = useState(defaultLocation.latitude);
  const [longitude, setLongitude] = useState(defaultLocation.longitude);
  const [locationLabel, setLocationLabel] = useState(
    `${defaultLocation.label} · ${defaultLocation.detail}`,
  );
  const [radiusKm, setRadiusKm] = useState("3");
  const [response, setResponse] = useState<SearchResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [locating, setLocating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedPlaceId, setSelectedPlaceId] = useState<string | null>(null);

  function applyLocation(location: ServiceLocation) {
    setLocationId(location.id);
    setLatitude(location.latitude);
    setLongitude(location.longitude);
    setLocationLabel(`${location.label} · ${location.detail}`);
  }

  async function runSearch(event?: FormEvent<HTMLFormElement>) {
    event?.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const result = await fetch("/api/search", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          query,
          mode: "HYBRID",
          latitude: Number(latitude),
          longitude: Number(longitude),
          radiusKm: Number(radiusKm),
          topK: 8,
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

  const runInitialSearch = useEffectEvent(() => {
    void runSearch();
  });

  useEffect(() => {
    runInitialSearch();
  }, []);

  const results = response?.results;

  useEffect(() => {
    if (!results?.length) {
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
    results?.find((place) => place.id === selectedPlaceId) ?? results?.[0] ?? null;

  return (
    <main className="service-shell">
      <section className="hero-stage">
        <div className="hero-visual" aria-hidden="true" />
        <div className="hero-scrim" />

        <div className="hero-copy">
          <p className="hero-brand">Lumo</p>
          <h1 className="hero-title">주변에서 원하는 분위기의 장소를 찾는 검색 서비스</h1>
          <p className="hero-support">
            리뷰 내용과 현재 위치를 함께 반영해 지금 가기 좋은 카페, 브런치,
            북카페를 찾아줍니다.
          </p>

          <form className="hero-search-form" onSubmit={runSearch}>
            <label className="hero-search-field">
              <span className="sr-only">검색어</span>
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="예: 조용하게 오래 머물 수 있는 카페"
              />
            </label>

            <div className="hero-action-row">
              <button className="hero-primary" type="submit" disabled={loading}>
                {loading ? "검색 중..." : "검색"}
              </button>
              <a className="hero-secondary" href="#search-settings">
                위치 바꾸기
              </a>
            </div>
          </form>
        </div>
      </section>

      <section className="settings-section" id="search-settings">
        <div className="section-intro">
          <h2>검색 기준</h2>
          <p>지역과 반경만 정하면 바로 검색할 수 있습니다.</p>
        </div>

        <div className="settings-row">
          <label className="control-field">
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

          <label className="control-field">
            <span>반경</span>
            <select
              value={radiusKm}
              onChange={(event) => setRadiusKm(event.target.value)}
            >
              {radiusOptions.map((option) => (
                <option key={option} value={option}>
                  {option}km
                </option>
              ))}
            </select>
          </label>

          <button
            className="ghost-button"
            type="button"
            onClick={requestCurrentLocation}
            disabled={locating}
          >
            {locating ? "위치 확인 중..." : "현재 위치 사용"}
          </button>

          <button
            className="solid-button"
            type="button"
            onClick={() => void runSearch()}
            disabled={loading}
          >
            다시 검색
          </button>
        </div>

        <div className="settings-meta">
          <p>기준 위치: {locationLabel}</p>
          <p>
            예시 검색:
            {exampleQueries.map((item) => (
              <button
                key={item}
                type="button"
                className="inline-link"
                onClick={() => setQuery(item)}
              >
                {item}
              </button>
            ))}
          </p>
        </div>

        {error ? <p className="error-box">{error}</p> : null}
      </section>

      <section className="results-section">
        <div className="section-intro">
          <h2>검색 결과</h2>
          <p>
            {response
              ? `"${response.query}"에 맞는 장소 ${response.total}개 중 추천 결과를 보여주고 있습니다.`
              : "검색 결과가 여기에 표시됩니다."}
          </p>
        </div>

        <div className="results-layout">
          <aside className="map-column">
            <div className="map-shell">
              <div className="map-header">
                <div>
                  <h3>지도</h3>
                  <p>
                    {selectedPlace
                      ? `${selectedPlace.name} 위치를 보고 있습니다.`
                      : "검색 결과를 지도에서 확인하세요."}
                  </p>
                </div>
                {selectedPlace?.distanceKm != null ? (
                  <span className="distance-pill">
                    {selectedPlace.distanceKm.toFixed(2)}km
                  </span>
                ) : null}
              </div>

              <SearchMap
                results={results ?? []}
                selectedPlaceId={selectedPlaceId}
                onSelectPlace={setSelectedPlaceId}
              />
            </div>
          </aside>

          <div className="result-list">
            {results?.length ? (
              results.map((place, index) => (
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
                <strong>검색 결과가 없습니다.</strong>
                <p>검색어를 바꾸거나 반경을 넓혀 다시 시도해 보세요.</p>
              </div>
            )}
          </div>
        </div>
      </section>
    </main>
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
  const mapUrl = `https://www.google.com/maps/search/?api=1&query=${place.latitude},${place.longitude}`;

  return (
    <article
      className={active ? "result-card active" : "result-card"}
      onClick={onSelect}
    >
      <div className="result-meta-row">
        <span className="rank-badge">추천 {index + 1}</span>
        {place.distanceKm !== null ? (
          <span className="distance-pill">{place.distanceKm.toFixed(2)}km</span>
        ) : null}
      </div>

      <div className="result-heading">
        <div>
          <h3>{place.name}</h3>
          <p>
            {place.category} · {place.district}
          </p>
        </div>
      </div>

      <p className="summary">{place.summary}</p>
      <p className="address-line">{place.roadAddress}</p>

      <div className="tag-row">
        {place.tags.slice(0, 4).map((tag) => (
          <span className="tag" key={`${place.id}-${tag}`}>
            {tag}
          </span>
        ))}
      </div>

      <div className="reason-block">
        <span>리뷰 근거</span>
        <blockquote>{place.evidence}</blockquote>
      </div>

      <div className="card-actions">
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

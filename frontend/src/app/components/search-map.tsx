"use client";

import { useEffect, useRef, useState } from "react";
import "leaflet/dist/leaflet.css";
import type { LayerGroup, Map as LeafletMap } from "leaflet";
import styles from "./search-map.module.css";
import type { PlaceResult } from "../search-types";

type SearchMapProps = {
  results: PlaceResult[];
  selectedPlaceId: string | null;
  hoveredPlaceId: string | null;
  onSelectPlace: (placeId: string) => void;
  onHoverPlace: (placeId: string | null) => void;
  searchCenter: { latitude: number; longitude: number } | null;
  radiusKm: number | null;
  clusterMode: boolean;
  routeModeEnabled: boolean;
  routeStops: PlaceResult[] | null;
  routeLengthKm: number | null;
};

const DEFAULT_CENTER: [number, number] = [36.3504, 127.8];
const DEFAULT_ZOOM = 7;
const FOCUS_ZOOM = 15;
const FOCUS_ZOOM_BUFFER = 0.35;

function isNear(a: number, b: number, tolerance = 0.00012): boolean {
  return Math.abs(a - b) <= tolerance;
}

function formatDistance(distanceKm: number | null): string {
  if (distanceKm == null) {
    return "거리 정보 없음";
  }

  return `${distanceKm.toFixed(2)} km`;
}

function markerMarkup(rank: number, isActive: boolean, isHovered: boolean) {
  const classes = [styles.leafletPin, isActive ? styles.leafletPinActive : "", isHovered ? styles.leafletPinHovered : ""]
    .filter(Boolean)
    .join(" ");
  return `
    <div class="${classes}">
      <span>${rank}</span>
    </div>
  `;
}

function clusterMarkup(count: number) {
  return `
    <div class="${styles.leafletClusterPin}">
      <span>${count}</span>
    </div>
  `;
}

function getRoutePin(rank: number, label: string) {
  return `
    <div class="${styles.leafletRoutePin}">
      <span>${label}</span>
      <strong>${rank}</strong>
    </div>
  `;
}

function buildClusters(places: PlaceResult[], zoom: number, minCount: number) {
  const clusterSize = zoom <= 8 ? 0.055 : zoom <= 11 ? 0.028 : zoom <= 13 ? 0.014 : 0.006;
  const clusters = new Map<
    string,
    {
      places: PlaceResult[];
      latitudeSum: number;
      longitudeSum: number;
    }
  >();

  for (const place of places) {
    const latKey = Math.round(place.latitude / clusterSize);
    const lngKey = Math.round(place.longitude / clusterSize);
    const key = `${latKey}:${lngKey}`;
    const bucket = clusters.get(key);

    if (!bucket) {
      clusters.set(key, {
        places: [place],
        latitudeSum: place.latitude,
        longitudeSum: place.longitude,
      });
    } else {
      bucket.places.push(place);
      bucket.latitudeSum += place.latitude;
      bucket.longitudeSum += place.longitude;
    }
  }

  return Array.from(clusters.values())
    .map((bucket) => ({
      ...bucket,
      count: bucket.places.length,
      latitude: bucket.latitudeSum / bucket.places.length,
      longitude: bucket.longitudeSum / bucket.places.length,
    }))
    .filter((bucket) => bucket.count >= minCount)
    .sort((a, b) => b.count - a.count);
}

export function SearchMap({
  results,
  selectedPlaceId,
  hoveredPlaceId,
  onSelectPlace,
  onHoverPlace,
  searchCenter,
  radiusKm,
  clusterMode,
  routeModeEnabled,
  routeStops,
  routeLengthKm,
}: SearchMapProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const markersRef = useRef<LayerGroup | null>(null);
  const routeLayerRef = useRef<LayerGroup | null>(null);
  const radiusLayerRef = useRef<LayerGroup | null>(null);
  const clusterLayerRef = useRef<LayerGroup | null>(null);
  const focusedPlaceIdRef = useRef<string | null>(null);
  const focusedViewportRef = useRef<{ latitude: number; longitude: number; zoom: number } | null>(null);
  const boundsSignatureRef = useRef("");
  const [isMapReady, setIsMapReady] = useState(false);

  const selectedPlace = results.find((place) => place.id === selectedPlaceId) ?? null;
  const hoveredPlace = results.find((place) => place.id === hoveredPlaceId) ?? null;
  const hasResults = results.length > 0;
  const activeTitle =
    hoveredPlace?.name ?? selectedPlace?.name ?? (hasResults ? `${results.length}개의 후보` : "지도 준비");
  const activeCopy = hoveredPlace
    ? `${hoveredPlace.name} 카드에서 하이라이트 중`
    : selectedPlace
      ? "선택한 장소를 중심으로 지도를 정렬했습니다."
      : hasResults
        ? "카드를 선택하면 해당 위치로 이동하고, 마커를 눌러도 동기화됩니다."
        : "검색어를 실행하면 결과가 지도에 표시됩니다.";
  const routeLabel = routeModeEnabled
    ? routeLengthKm !== null && routeStops !== null && routeStops.length > 1
      ? `추천 경로: ${routeStops.length}개 정거장 · ${routeLengthKm.toFixed(2)}km`
      : "경로 모드: 후보가 부족합니다"
    : clusterMode
      ? "클러스터 ON"
      : "클러스터 OFF";

  useEffect(() => {
    let cancelled = false;
    let resizeObserver: ResizeObserver | null = null;

    async function bootMap() {
      if (!containerRef.current || mapRef.current) {
        return;
      }

      try {
        const L = await import("leaflet");
        if (cancelled || !containerRef.current) {
          return;
        }

        const map = L.map(containerRef.current, {
          zoomControl: false,
          preferCanvas: true,
          scrollWheelZoom: false,
          zoomSnap: 0.5,
          zoomDelta: 0.5,
        }).setView(DEFAULT_CENTER, DEFAULT_ZOOM);

        L.control.zoom({ position: "topright" }).addTo(map);
        L.control.scale({ imperial: false, maxWidth: 120, position: "bottomleft" }).addTo(map);

        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          attribution: "&copy; OpenStreetMap contributors",
          crossOrigin: true,
          detectRetina: true,
          keepBuffer: 3,
          maxZoom: 19,
          maxNativeZoom: 19,
          updateWhenIdle: true,
          updateWhenZooming: false,
        }).addTo(map);

        markersRef.current = L.layerGroup().addTo(map);
        routeLayerRef.current = L.layerGroup().addTo(map);
        radiusLayerRef.current = L.layerGroup().addTo(map);
        clusterLayerRef.current = L.layerGroup().addTo(map);

        resizeObserver = new ResizeObserver(() => {
          map.invalidateSize({ animate: false });
        });
        resizeObserver.observe(containerRef.current);
        window.requestAnimationFrame(() => {
          map.invalidateSize({ animate: false });
        });

        mapRef.current = map;
        setIsMapReady(true);
      } catch (error) {
        console.error("Leaflet bootstrap failed", error);
      }
    }

    void bootMap();

    return () => {
      cancelled = true;
      resizeObserver?.disconnect();
      resizeObserver = null;
      routeLayerRef.current?.clearLayers();
      routeLayerRef.current = null;
      radiusLayerRef.current?.clearLayers();
      radiusLayerRef.current = null;
      clusterLayerRef.current?.clearLayers();
      clusterLayerRef.current = null;
      markersRef.current?.clearLayers();
      markersRef.current = null;
      setIsMapReady(false);
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function syncMapLayers() {
      const L = await import("leaflet");
      if (cancelled || !isMapReady || !mapRef.current || !markersRef.current || !routeLayerRef.current || !radiusLayerRef.current || !clusterLayerRef.current) {
        return;
      }

      const map = mapRef.current;
      const markerLayer = markersRef.current;
      const routeLayer = routeLayerRef.current;
      const radiusLayer = radiusLayerRef.current;
      const clusterLayer = clusterLayerRef.current;

      markerLayer.clearLayers();
      routeLayer.clearLayers();
      radiusLayer.clearLayers();
      clusterLayer.clearLayers();

      if (!results.length) {
        focusedPlaceIdRef.current = null;
        focusedViewportRef.current = null;
        map.setView(DEFAULT_CENTER, DEFAULT_ZOOM);
        return;
      }

      if (searchCenter && radiusKm !== null && radiusKm > 0) {
        L.circle([searchCenter.latitude, searchCenter.longitude], {
          color: "#0071e3",
          fillColor: "#dbeafe",
          fillOpacity: 0.14,
          radius: radiusKm * 1000,
          weight: 2,
          opacity: 0.65,
        }).addTo(radiusLayer);
      }

      for (const [index, place] of results.entries()) {
        const marker = L.marker([place.latitude, place.longitude], {
          icon: L.divIcon({
            className: "",
            html: markerMarkup(
              index + 1,
              place.id === selectedPlaceId,
              place.id === hoveredPlaceId,
            ),
            iconSize: [42, 42],
            iconAnchor: [21, 21],
          }),
        });

        marker.on("click", () => onSelectPlace(place.id));
        marker.on("mouseover", () => onHoverPlace(place.id));
        marker.on("mouseout", () => onHoverPlace(null));
        const distanceText = formatDistance(place.distanceKm);
        marker.bindTooltip(
          `<strong>${place.name}</strong><br/>거리 ${distanceText}<br/>${place.summary}`,
          {
            direction: "top",
            offset: [0, -18],
          },
        );
        markerLayer.addLayer(marker);
      }

      if (routeStops && routeStops.length > 1) {
        const routeCoordinates = routeStops.map((place) => [place.latitude, place.longitude] as [number, number]);
        L.polyline(routeCoordinates, {
          color: "#ff5a1f",
          weight: 5,
          opacity: 0.95,
        }).addTo(routeLayer);

        routeStops.forEach((stop, routeIndex) => {
          const marker = L.marker([stop.latitude, stop.longitude], {
            icon: L.divIcon({
              className: "",
              html: getRoutePin(routeIndex + 1, routeIndex === 0 ? "S" : routeIndex === routeStops.length - 1 ? "E" : String(routeIndex + 1)),
              iconSize: [36, 36],
              iconAnchor: [18, 18],
            }),
          });

          marker.bindTooltip(`${routeIndex + 1}. ${stop.name}`, {
            direction: "bottom",
            offset: [0, 12],
          });
          marker.addTo(routeLayer);
        });
      }

      if (clusterMode) {
        const clusters = buildClusters(results, map.getZoom(), 2);
        for (const cluster of clusters) {
          const clusterMarker = L.marker([cluster.latitude, cluster.longitude], {
            icon: L.divIcon({
              className: "",
              html: clusterMarkup(cluster.count),
              iconSize: [44, 44],
              iconAnchor: [22, 22],
            }),
          });
          const clusterBounds = L.latLngBounds(
            cluster.places.map((place) => [place.latitude, place.longitude] as [number, number]),
          );
          clusterMarker.on("click", () => {
            map.fitBounds(clusterBounds.pad(0.32), { animate: true, duration: 0.6 });
          });
          clusterMarker.bindTooltip(`${cluster.count}개 후보`, { direction: "top", offset: [0, -16] });
          clusterLayer.addLayer(clusterMarker);
        }
      }

      if (selectedPlace) {
        L.circleMarker([selectedPlace.latitude, selectedPlace.longitude], {
          radius: 28,
          color: "#0071e3",
          fillColor: "#2997ff",
          fillOpacity: 0.2,
          weight: 2.8,
          opacity: 0.92,
        }).addTo(markerLayer);

        const isFocusTargetNew = focusedPlaceIdRef.current !== selectedPlace.id;
        const isZoomFarEnough = map.getZoom() < FOCUS_ZOOM - FOCUS_ZOOM_BUFFER;
        const mapCenter = map.getCenter();
        const isCenterAligned =
          isNear(mapCenter.lat, selectedPlace.latitude, 0.00022) &&
          isNear(mapCenter.lng, selectedPlace.longitude, 0.00022);
        const previousFocus = focusedViewportRef.current;
        const isStillFocused =
          !isFocusTargetNew &&
          !!previousFocus &&
          isNear(previousFocus.latitude, mapCenter.lat, 0.00022) &&
          isNear(previousFocus.longitude, mapCenter.lng, 0.00022) &&
          isNear(previousFocus.zoom, map.getZoom(), 0.01);
        const selectedZoom = Math.max(Math.min(FOCUS_ZOOM, map.getMaxZoom() ?? FOCUS_ZOOM), 3);

        if (!isStillFocused || isZoomFarEnough || !isCenterAligned) {
          map.stop();
          map.flyTo([selectedPlace.latitude, selectedPlace.longitude], selectedZoom, {
            animate: true,
            duration: 0.55,
            easeLinearity: 0.2,
          });
        }

        focusedPlaceIdRef.current = selectedPlace.id;
        focusedViewportRef.current = {
          latitude: selectedPlace.latitude,
          longitude: selectedPlace.longitude,
          zoom: selectedZoom,
        };
        return;
      }

      const boundsKey = results
        .map((place) => `${place.id}:${place.latitude.toFixed(6)},${place.longitude.toFixed(6)}`)
        .join("|");
      if (boundsSignatureRef.current !== boundsKey) {
        const bounds = L.latLngBounds(
          results.map((place) => [place.latitude, place.longitude] as [number, number]),
        );
        map.fitBounds(bounds.pad(0.22), { animate: true, duration: 0.6 });
        boundsSignatureRef.current = boundsKey;
      }

      focusedPlaceIdRef.current = null;
    }

    void syncMapLayers();

    return () => {
      cancelled = true;
    };
  }, [
    results,
    selectedPlace,
    selectedPlaceId,
    hoveredPlaceId,
    onSelectPlace,
    onHoverPlace,
    isMapReady,
    routeLengthKm,
    routeStops,
    radiusKm,
    clusterMode,
    routeModeEnabled,
    searchCenter,
  ]);

  return (
    <div className={styles.mapShell}>
      <p className={styles.mapHeader}>
        <strong>검색 지도</strong>
        <span>OpenStreetMap 기반 지도</span>
      </p>
      <div className={styles.mapCanvas} ref={containerRef} />
      <div className={`${styles.mapOverlay} ${styles.mapOverlayTop}`}>
        <span className={styles.badge}>지도 현황</span>
        <strong>{activeTitle}</strong>
        <p>{activeCopy}</p>
      </div>
      <div className={`${styles.mapOverlay} ${styles.mapOverlayBottom}`}>
        <span className={styles.badgeMuted}>{selectedPlace ? "선택됨" : hoveredPlaceId ? "하이라이트" : "브라우징"}</span>
        <span className={styles.badgeMuted}>{results.length} results</span>
        <span className={styles.badgeMuted}>{routeLabel}</span>
      </div>
    </div>
  );
}

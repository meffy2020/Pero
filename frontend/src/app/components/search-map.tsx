"use client";

import { useEffect, useRef } from "react";
import "leaflet/dist/leaflet.css";
import type { LayerGroup, Map as LeafletMap, TileLayer } from "leaflet";
import styles from "./search-map.module.css";
import type { PlaceComparisonItem } from "../search-types";

type SearchMapProps = {
  results: PlaceComparisonItem[];
  selectedPlaceId: string | null;
  hoveredPlaceId: string | null;
  comparedPlaceIds: string[];
  onSelectPlace: (placeId: string) => void;
  searchCenter: { latitude: number; longitude: number } | null;
  radiusKm: number | null;
  routeStops: PlaceComparisonItem[];
  showClusters: boolean;
  activeViewLabel: string;
};

const DEFAULT_CENTER: [number, number] = [36.35, 127.8];
const DEFAULT_ZOOM = 12;
const FOCUS_ZOOM = 15;
const LIGHT_TILE_URL = "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png";
const FALLBACK_TILE_URL = "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png";
const MARKER_ASSETS = [
  "/markers/marker-default.svg",
  "/markers/marker-event.svg",
  "/markers/marker-pet.svg",
  "/markers/marker-accessible.svg",
  "/markers/marker-family.svg",
  "/markers/marker-culture.svg",
  "/markers/marker-nature.svg",
];

function markerAsset(place: PlaceComparisonItem): string {
  const tags = place.themeTags ?? [];

  if (tags.includes("축제행사")) {
    return "/markers/marker-event.svg";
  }
  if (tags.includes("반려동물동반")) {
    return "/markers/marker-pet.svg";
  }
  if (tags.includes("무장애여행")) {
    return "/markers/marker-accessible.svg";
  }
  if (tags.includes("가족나들이")) {
    return "/markers/marker-family.svg";
  }
  if (tags.includes("실내데이트")) {
    return "/markers/marker-culture.svg";
  }
  if (tags.includes("자연산책")) {
    return "/markers/marker-nature.svg";
  }
  return "/markers/marker-default.svg";
}

function markerMarkup(place: PlaceComparisonItem, isActive: boolean, isHovered: boolean) {
  const classes = [
    styles.markerPin,
    isActive ? styles.markerPinActive : "",
    isHovered ? styles.markerPinHovered : "",
  ]
    .filter(Boolean)
    .join(" ");

  return `
    <div class="${classes}">
      <span class="${styles.markerPulse}"></span>
      <img class="${styles.markerImage}" src="${markerAsset(place)}" alt="" />
    </div>
  `;
}

function safeInvalidateSize(map: LeafletMap) {
  const container = map.getContainer();
  if (!container.isConnected || container.clientWidth === 0 || container.clientHeight === 0) {
    return;
  }

  try {
    map.invalidateSize({ animate: false });
  } catch {
    // ignore transient layout races
  }
}

function createTileLayer(L: typeof import("leaflet"), url: string): TileLayer {
  return L.tileLayer(url, {
    attribution: "&copy; OpenStreetMap contributors &copy; CARTO",
    crossOrigin: true,
    detectRetina: true,
    maxZoom: 19,
    maxNativeZoom: 19,
    updateWhenIdle: true,
    updateWhenZooming: false,
  });
}

function preloadMarkerAssets() {
  if (typeof window === "undefined") {
    return;
  }

  for (const asset of MARKER_ASSETS) {
    const image = new window.Image();
    image.decoding = "async";
    image.src = asset;
  }
}

export function SearchMap({
  results,
  selectedPlaceId,
  hoveredPlaceId,
  onSelectPlace,
  searchCenter,
  radiusKm,
}: SearchMapProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const tileLayerRef = useRef<TileLayer | null>(null);
  const markersRef = useRef<LayerGroup | null>(null);
  const radiusLayerRef = useRef<LayerGroup | null>(null);
  const leafletRef = useRef<typeof import("leaflet") | null>(null);
  const focusedPlaceIdRef = useRef<string | null>(null);
  const boundsSignatureRef = useRef("");

  useEffect(() => {
    let cancelled = false;
    let resizeObserver: ResizeObserver | null = null;

    async function bootMap() {
      if (!containerRef.current || mapRef.current) {
        return;
      }

      preloadMarkerAssets();

      const L = leafletRef.current ?? (await import("leaflet"));
      leafletRef.current = L;
      if (cancelled || !containerRef.current) {
        return;
      }

      const map = L.map(containerRef.current, {
        zoomControl: false,
        zoomSnap: 0.5,
        zoomDelta: 0.5,
      }).setView(DEFAULT_CENTER, DEFAULT_ZOOM);

      L.control.zoom({ position: "bottomright" }).addTo(map);

      const primaryLayer = createTileLayer(L, LIGHT_TILE_URL);
      const fallbackLayer = createTileLayer(L, FALLBACK_TILE_URL);
      let fallbackActivated = false;

      primaryLayer.on("tileerror", () => {
        if (fallbackActivated || !map.hasLayer(primaryLayer)) {
          return;
        }
        fallbackActivated = true;
        map.removeLayer(primaryLayer);
        fallbackLayer.addTo(map);
        tileLayerRef.current = fallbackLayer;
      });

      primaryLayer.addTo(map);
      tileLayerRef.current = primaryLayer;
      markersRef.current = L.layerGroup().addTo(map);
      radiusLayerRef.current = L.layerGroup().addTo(map);
      mapRef.current = map;

      resizeObserver = new ResizeObserver(() => {
        safeInvalidateSize(map);
      });
      resizeObserver.observe(containerRef.current);

      map.whenReady(() => {
        window.requestAnimationFrame(() => safeInvalidateSize(map));
        window.setTimeout(() => safeInvalidateSize(map), 120);
      });
    }

    void bootMap();

    return () => {
      cancelled = true;
      resizeObserver?.disconnect();
      markersRef.current?.clearLayers();
      markersRef.current = null;
      radiusLayerRef.current?.clearLayers();
      radiusLayerRef.current = null;
      tileLayerRef.current = null;
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function syncMarkers() {
      const map = mapRef.current;
      const markersLayer = markersRef.current;
      const radiusLayer = radiusLayerRef.current;
      if (!map || !markersLayer || !radiusLayer) {
        return;
      }

      const L = leafletRef.current ?? (await import("leaflet"));
      leafletRef.current = L;
      if (cancelled) {
        return;
      }

      markersLayer.clearLayers();
      radiusLayer.clearLayers();

      if (searchCenter && radiusKm) {
        L.circle([searchCenter.latitude, searchCenter.longitude], {
          radius: radiusKm * 1000,
          color: "rgba(23, 23, 23, 0.14)",
          weight: 1,
          fillColor: "rgba(255, 255, 255, 0.08)",
          fillOpacity: 0.45,
          interactive: false,
        }).addTo(radiusLayer);
      }

      results.forEach((place) => {
        const marker = L.marker([place.latitude, place.longitude], {
          icon: L.divIcon({
            className: styles.markerWrapper,
            html: markerMarkup(place, place.id === selectedPlaceId, place.id === hoveredPlaceId),
            iconSize: [48, 60],
            iconAnchor: [24, 54],
          }),
        });

        marker.on("click", () => onSelectPlace(place.id));
        marker.bindTooltip(place.name, { direction: "top", offset: [0, -12] });
        marker.addTo(markersLayer);
      });

      if (selectedPlaceId) {
        const selectedPlace = results.find((place) => place.id === selectedPlaceId) ?? null;
        if (selectedPlace && focusedPlaceIdRef.current !== selectedPlace.id) {
          focusedPlaceIdRef.current = selectedPlace.id;
          map.flyTo([selectedPlace.latitude, selectedPlace.longitude], FOCUS_ZOOM, {
            duration: 0.55,
            easeLinearity: 0.4,
          });
          return;
        }
      }

      if (results.length === 0) {
        focusedPlaceIdRef.current = null;
        boundsSignatureRef.current = "";
        map.setView(searchCenter ? [searchCenter.latitude, searchCenter.longitude] : DEFAULT_CENTER, DEFAULT_ZOOM);
        return;
      }

      const signature = results.map((place) => place.id).join("|");
      const shouldRefitBounds = signature !== boundsSignatureRef.current;
      if (shouldRefitBounds) {
        if (!selectedPlaceId) {
          focusedPlaceIdRef.current = null;
        }
        boundsSignatureRef.current = signature;
        const bounds = L.latLngBounds(results.map((place) => [place.latitude, place.longitude] as [number, number]));
        map.fitBounds(bounds.pad(0.2), { maxZoom: FOCUS_ZOOM - 1, animate: true, duration: 0.4 });
      }
    }

    void syncMarkers();

    return () => {
      cancelled = true;
    };
  }, [results, selectedPlaceId, hoveredPlaceId, onSelectPlace, radiusKm, searchCenter]);

  return (
    <div className={styles.mapShell}>
      <div ref={containerRef} className={styles.mapCanvas} />
    </div>
  );
}

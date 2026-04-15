"use client";

import { useEffect, useRef } from "react";
import "leaflet/dist/leaflet.css";
import type { LayerGroup, Map as LeafletMap } from "leaflet";
import type { PlaceResult } from "../search-types";

type SearchMapProps = {
  results: PlaceResult[];
  selectedPlaceId: string | null;
  onSelectPlace: (placeId: string) => void;
};

const DEFAULT_CENTER: [number, number] = [37.5535, 126.9221];
const DEFAULT_ZOOM = 13;

function markerMarkup(rank: number, active: boolean) {
  const stateClass = active ? "is-active" : "";
  return `
    <div class="leaflet-pin ${stateClass}">
      <span>${rank}</span>
    </div>
  `;
}

export function SearchMap({
  results,
  selectedPlaceId,
  onSelectPlace,
}: SearchMapProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const markersRef = useRef<LayerGroup | null>(null);
  const selectedPlace = results.find((place) => place.id === selectedPlaceId) ?? null;
  const hasResults = results.length > 0;
  const activeTitle = selectedPlace?.name ?? (hasResults ? `${results.length} places in view` : "No places in view");
  const activeCopy = selectedPlace
    ? "Selected result is centered on the map."
    : hasResults
      ? "Pick a result to anchor the map and compare nearby places."
      : "Run a search to populate the map surface.";

  useEffect(() => {
    let cancelled = false;
    let resizeObserver: ResizeObserver | null = null;

    async function bootMap() {
      if (!containerRef.current || mapRef.current) {
        return;
      }

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
      L.control.scale({
        imperial: false,
        maxWidth: 120,
        position: "bottomleft",
      }).addTo(map);

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
      resizeObserver = new ResizeObserver(() => {
        map.invalidateSize({ animate: false });
      });
      resizeObserver.observe(containerRef.current);
      window.requestAnimationFrame(() => {
        map.invalidateSize({ animate: false });
      });
      mapRef.current = map;
    }

    void bootMap();

    return () => {
      cancelled = true;
      resizeObserver?.disconnect();
      resizeObserver = null;
      markersRef.current?.clearLayers();
      markersRef.current = null;
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function syncMarkers() {
      const L = await import("leaflet");
      if (cancelled || !mapRef.current || !markersRef.current) {
        return;
      }

      const map = mapRef.current;
      const markerLayer = markersRef.current;
      markerLayer.clearLayers();

      if (!results.length) {
        map.setView(DEFAULT_CENTER, DEFAULT_ZOOM);
        return;
      }

      for (const [index, place] of results.entries()) {
        const marker = L.marker([place.latitude, place.longitude], {
          icon: L.divIcon({
            className: "leaflet-pin-shell",
            html: markerMarkup(index + 1, place.id === selectedPlaceId),
            iconSize: [42, 42],
            iconAnchor: [21, 21],
          }),
        });

        marker.on("click", () => onSelectPlace(place.id));
        marker.bindTooltip(place.name, {
          direction: "top",
          offset: [0, -18],
        });
        markerLayer.addLayer(marker);
      }

      if (selectedPlace) {
        map.flyTo([selectedPlace.latitude, selectedPlace.longitude], 15, {
          animate: true,
          duration: 0.55,
          easeLinearity: 0.2,
        });
        return;
      }

      const bounds = L.latLngBounds(
        results.map((place) => [place.latitude, place.longitude] as [number, number]),
      );
      map.fitBounds(bounds.pad(0.22), {
        animate: true,
        duration: 0.6,
      });
    }

    void syncMarkers();

    return () => {
      cancelled = true;
    };
  }, [onSelectPlace, results, selectedPlace, selectedPlaceId]);

  if (!results.length) {
    return (
      <div className="map-panel map-panel-live map-panel-empty">
        <div className="map-title">
          <strong>검색 지도</strong>
          <span>OpenStreetMap 기반 지도 표면을 유지한 채 검색 결과를 기다립니다.</span>
        </div>
        <div className="leaflet-stage" ref={containerRef} />
        <div className="map-overlay map-overlay-empty">
          <span className="map-overlay-badge">OpenStreetMap</span>
          <strong>No places in view</strong>
          <p>Run a search to populate the map surface.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="map-panel map-panel-live map-panel-has-results">
      <div className="map-title">
        <strong>검색 지도</strong>
        <span>
          검색된 장소를 지도에서 비교할 수 있습니다. 카드를 누르면 해당 위치로
          이동합니다.
        </span>
      </div>
      <div className="leaflet-stage" ref={containerRef} />
      <div className="map-overlay map-overlay-top">
        <span className="map-overlay-badge">OpenStreetMap</span>
        <strong>{activeTitle}</strong>
        <p>{activeCopy}</p>
      </div>
      <div className="map-overlay map-overlay-bottom">
        <span className="map-overlay-chip">{selectedPlace ? "Focused" : "Browsing"}</span>
        <span className="map-overlay-chip">{results.length} results</span>
      </div>
    </div>
  );
}

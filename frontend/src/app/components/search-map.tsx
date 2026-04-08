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

  useEffect(() => {
    let cancelled = false;

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
      }).setView(DEFAULT_CENTER, DEFAULT_ZOOM);

      L.control.zoom({ position: "topright" }).addTo(map);

      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: "&copy; OpenStreetMap contributors",
        maxZoom: 19,
      }).addTo(map);

      markersRef.current = L.layerGroup().addTo(map);
      mapRef.current = map;
    }

    void bootMap();

    return () => {
      cancelled = true;
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

      const selectedPlace = results.find((place) => place.id === selectedPlaceId);
      if (selectedPlace) {
        map.flyTo([selectedPlace.latitude, selectedPlace.longitude], 15, {
          animate: true,
          duration: 0.45,
        });
        return;
      }

      const bounds = L.latLngBounds(
        results.map((place) => [place.latitude, place.longitude] as [number, number]),
      );
      map.fitBounds(bounds.pad(0.22), { animate: true });
    }

    void syncMarkers();

    return () => {
      cancelled = true;
    };
  }, [onSelectPlace, results, selectedPlaceId]);

  if (!results.length) {
    return (
      <div className="map-panel empty">
        <p>지도에 표시할 장소가 없습니다. 필터를 풀거나 다시 검색해 보세요.</p>
      </div>
    );
  }

  return (
    <div className="map-panel map-panel-live">
      <div className="map-title">
        <strong>검색 지도</strong>
        <span>
          검색된 장소를 지도에서 비교할 수 있습니다. 카드를 누르면 해당 위치로
          이동합니다.
        </span>
      </div>
      <div className="leaflet-stage" ref={containerRef} />
    </div>
  );
}

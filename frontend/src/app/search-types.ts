export type SearchMode = "KEYWORD" | "VECTOR" | "HYBRID";

export type PlaceResult = {
  id: string;
  name: string;
  category: string;
  district: string;
  summary: string;
  tags: string[];
  latitude: number;
  longitude: number;
  distanceKm: number | null;
  evidence: string;
  keywordScore: number;
  vectorScore: number;
  featureScore: number;
  geoScore: number;
  finalScore: number;
};

export type SearchResponse = {
  query: string;
  mode: SearchMode;
  total: number;
  topK: number;
  generatedAt: string;
  results: PlaceResult[];
};

export type SearchMode = "KEYWORD" | "VECTOR" | "HYBRID";

export type PlaceResult = {
  id: string;
  name: string;
  category: string;
  district: string;
  address: string;
  roadAddress: string;
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

export type RecommendationPlace = {
  id: string;
  name: string;
  category: string;
  district: string;
  roadAddress: string;
  summary: string;
  tags: string[];
  latitude: number;
  longitude: number;
  distanceKm: number | null;
  reason: string;
};

export type RecommendationCard = {
  key: string;
  title: string;
  description: string;
  place: RecommendationPlace;
};

export type DateCourseStop = {
  slot: string;
  place: RecommendationPlace;
};

export type DateCourse = {
  title: string;
  description: string;
  stops: DateCourseStop[];
};

export type SearchResponse = {
  query: string;
  mode: SearchMode;
  total: number;
  topK: number;
  generatedAt: string;
  results: PlaceResult[];
};

export type RecommendationResponse = {
  generatedAt: string;
  fallbackUsed: boolean;
  nearbyPick: RecommendationCard;
  mealPick: RecommendationCard;
  dateCourse: DateCourse;
};

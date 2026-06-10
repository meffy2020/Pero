export type SearchMode = "KEYWORD" | "VECTOR" | "HYBRID";
export type CommandView = "themes" | "ops" | "compare" | "intel";
export type ThemeScope = "seoul" | "nationwide";
export type ThemeSource = "smartSeoul" | "koreaTour" | "merged";
export type SourceAttribution = ThemeSource | string;

export type TourCommonDetail = {
  tel?: string | null;
  homepage?: string | null;
  overview?: string | null;
  bookTour?: string | null;
  infoCenter?: string | null;
  restDate?: string | null;
  useTime?: string | null;
  parking?: string | null;
  useFee?: string | null;
  refundPolicy?: string | null;
  expGuide?: string | null;
  accomCount?: string | null;
  chkInTime?: string | null;
  chkOutTime?: string | null;
  subFacility?: string | null;
  parkingFee?: string | null;
  scale?: string | null;
  spendTime?: string | null;
  eventStartDate?: string | null;
  eventEndDate?: string | null;
  playTime?: string | null;
  ageLimit?: string | null;
};

export type TourImageDetail = {
  originImgUrl?: string | null;
  smallImageUrl?: string | null;
  imgName?: string | null;
  serialNum?: string | null;
};

export type TourPetDetail = {
  petTursmInfo?: string | null;
  acmpyTypeCd?: string | null;
  relaPosesFclty?: string | null;
  relaFrnshPrdlst?: string | null;
  etcAcmpyInfo?: string | null;
  relaPurcPrdlst?: string | null;
  acmpyPsblCpam?: string | null;
};

export type TourApiDetail = {
  contentId?: string | null;
  contentTypeId?: string | null;
  contentTypeLabel?: string | null;
  common?: TourCommonDetail | null;
  intro?: Record<string, string> | null;
  images?: TourImageDetail[] | null;
  pet?: TourPetDetail | null;
};

export type SearchSourceMeta = {
  providerId: string;
  providerName: string;
  status: string;
  generatedAt: string | null;
  count: number;
};

export type PlaceResult = {
  id: string;
  name: string;
  category: string;
  district: string;
  address: string;
  roadAddress: string;
  summary: string;
  tags: string[];
  themeTags: string[];
  latitude: number;
  longitude: number;
  sourceAttribution: SourceAttribution;
  distanceKm: number | null;
  evidence: string;
  keywordScore: number;
  vectorScore: number;
  featureScore: number;
  geoScore: number;
  finalScore: number;
  tourApi?: TourApiDetail | null;
};

export type SearchResponse = {
  query: string;
  themeId?: string | null;
  mode: SearchMode;
  total: number;
  topK: number;
  generatedAt: string;
  source?: SearchSourceMeta | null;
  results: PlaceResult[];
};

export type RecommendationPlace = {
  id: string;
  name: string;
  category: string;
  district: string;
  roadAddress: string;
  summary: string;
  tags: string[];
  themeTags: string[];
  latitude: number;
  longitude: number;
  sourceAttribution: SourceAttribution;
  distanceKm: number | null;
  reason: string;
  tourApi?: TourApiDetail | null;
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

export type RecommendationsResponse = {
  generatedAt: string;
  fallbackUsed: boolean;
  nearbyPick?: RecommendationCard | null;
  mealPick?: RecommendationCard | null;
  dateCourse?: DateCourse | null;
};

export type PlaceListItem = {
  id: string;
  name: string;
  category: string;
  district: string;
  address: string;
  roadAddress: string;
  summary: string;
  tags: string[];
  themeTags: string[];
  latitude: number;
  longitude: number;
  sourceAttribution: SourceAttribution;
  tourApi?: TourApiDetail | null;
};

export type PlacesResponse = {
  source?: SearchSourceMeta | null;
  total: number;
  places: PlaceListItem[];
};

export type ThemePlace = {
  id: string;
  name: string;
  category: string;
  district: string;
  address: string;
  roadAddress: string;
  summary: string;
  tags: string[];
  themeTags: string[];
  latitude: number;
  longitude: number;
  sourceAttribution: SourceAttribution;
  reason: string;
  tourApi?: TourApiDetail | null;
};

export type ThemeEvent = {
  id: string;
  title: string;
  status: string;
  startDate?: string | null;
  endDate?: string | null;
  periodLabel: string;
  district: string;
  venue: string;
  latitude: number;
  longitude: number;
  sourceAttribution: SourceAttribution;
  summary: string;
  themeId: string;
  relatedPlaceId?: string | null;
};

export type ThemeSummary = {
  themeId: string;
  title: string;
  scope: ThemeScope;
  source: ThemeSource;
  badge: string;
  summary: string;
  heroPlaces: ThemePlace[];
  heroEventCount: number;
};

export type ThemeDetail = {
  themeId: string;
  title: string;
  scope: ThemeScope;
  source: ThemeSource;
  badge: string;
  summary: string;
  generatedAt: string;
  center: { latitude: number; longitude: number };
  smartSeoulLayerEnabled: boolean;
  sourceAttributions: string[];
  places: ThemePlace[];
  events: ThemeEvent[];
};

export type EventsResponse = {
  generatedAt: string;
  total: number;
  events: ThemeEvent[];
};

export type PlaceComparisonItem = {
  id: string;
  name: string;
  category: string;
  district: string;
  roadAddress: string;
  summary: string;
  tags: string[];
  themeTags: string[];
  latitude: number;
  longitude: number;
  sourceAttribution: SourceAttribution;
  distanceKm?: number | null;
  reason?: string | null;
  evidence?: string | null;
  tourApi?: TourApiDetail | null;
};

export type CompareSlot = {
  slot: number;
  place: PlaceComparisonItem | null;
};

export type IntelSummary = {
  totalPlaces: number;
  totalThemes: number;
  totalEvents: number;
  withTourApi: number;
  withImages: number;
  districtCount: number;
  categoryCount: number;
  providerName: string;
  providerStatus: string;
  generatedAt: string | null;
};

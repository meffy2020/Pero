import Foundation

public struct PlaceListItem: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: String
    public let district: String
    public let address: String
    public let roadAddress: String
    public let summary: String
    public let tags: [String]
    public let themeTags: [String]
    public let latitude: Double
    public let longitude: Double
    public let sourceAttribution: String
    public let tourApi: TourAPI?
}

public struct PlaceResult: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: String
    public let district: String
    public let address: String
    public let roadAddress: String
    public let summary: String
    public let tags: [String]
    public let themeTags: [String]
    public let latitude: Double
    public let longitude: Double
    public let sourceAttribution: String
    public let distanceKm: Double?
    public let evidence: String
    public let keywordScore: Double
    public let vectorScore: Double
    public let featureScore: Double
    public let geoScore: Double
    public let finalScore: Double
    public let tourApi: TourAPI?
}

public struct RecommendationPlace: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: String
    public let district: String
    public let roadAddress: String
    public let summary: String
    public let tags: [String]
    public let themeTags: [String]
    public let latitude: Double
    public let longitude: Double
    public let sourceAttribution: String
    public let distanceKm: Double?
    public let reason: String
    public let tourApi: TourAPI?
}

public struct TourAPI: Decodable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case contentId
        case contentTypeId
        case contentTypeLabel
        case common
        case intro
        case images
        case pet
    }

    public let contentId: String?
    public let contentTypeId: String?
    public let contentTypeLabel: String?
    public let common: TourCommon?
    public let intro: [String: String]?
    public let images: [TourImage]
    public let pet: TourPet?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentId = try container.decodeIfPresent(String.self, forKey: .contentId)
        self.contentTypeId = try container.decodeIfPresent(String.self, forKey: .contentTypeId)
        self.contentTypeLabel = try container.decodeIfPresent(String.self, forKey: .contentTypeLabel)
        self.common = try container.decodeIfPresent(TourCommon.self, forKey: .common)
        self.intro = try container.decodeIfPresent([String: String].self, forKey: .intro)
        self.images = try container.decodeIfPresent([TourImage].self, forKey: .images) ?? []
        self.pet = try container.decodeIfPresent(TourPet.self, forKey: .pet)
    }
}

public struct TourCommon: Decodable, Equatable, Sendable {
    public let tel: String?
    public let homepage: String?
    public let overview: String?
    public let bookTour: String?
    public let infoCenter: String?
    public let restDate: String?
    public let useTime: String?
    public let parking: String?
    public let useFee: String?
    public let refundPolicy: String?
    public let expGuide: String?
    public let accomCount: String?
    public let chkInTime: String?
    public let chkOutTime: String?
    public let subFacility: String?
    public let parkingFee: String?
    public let scale: String?
    public let spendTime: String?
    public let eventStartDate: String?
    public let eventEndDate: String?
    public let playTime: String?
    public let ageLimit: String?
}

public struct TourImage: Decodable, Equatable, Sendable {
    public let originImgUrl: String?
    public let smallImageUrl: String?
    public let imgName: String?
    public let serialNum: String?
}

public struct TourPet: Decodable, Equatable, Sendable {
    public let petTursmInfo: String?
    public let acmpyTypeCd: String?
    public let relaPosesFclty: String?
    public let relaFrnshPrdlst: String?
    public let etcAcmpyInfo: String?
    public let relaPurcPrdlst: String?
    public let acmpyPsblCpam: String?
}

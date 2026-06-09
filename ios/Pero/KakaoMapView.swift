import SwiftUI
import UIKit
import KakaoMapsSDK

struct KakaoMapCamera: Equatable {
    var latitude: Double
    var longitude: Double
    var level: Int

    static let seoul = KakaoMapCamera(latitude: 37.5665, longitude: 126.9780, level: 8)
    static let focusedLevel = 11
}

struct KakaoMapVisibleBounds: Equatable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    var latitudeSpan: Double {
        maxLatitude - minLatitude
    }

    var longitudeSpan: Double {
        maxLongitude - minLongitude
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLatitude
        && latitude <= maxLatitude
        && longitude >= minLongitude
        && longitude <= maxLongitude
    }

    func isReadableMarkerDensity(for visibleCandidateCount: Int) -> Bool {
        guard visibleCandidateCount > 0 else { return false }
        if latitudeSpan <= 0.18, longitudeSpan <= 0.18 {
            return visibleCandidateCount <= 180
        }
        if latitudeSpan <= 0.35, longitudeSpan <= 0.35 {
            return visibleCandidateCount <= 90
        }
        if latitudeSpan <= 0.7, longitudeSpan <= 0.7 {
            return visibleCandidateCount <= 45
        }
        return visibleCandidateCount <= 18
    }
}

struct KakaoMapMarker: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case attraction
        case restaurant
        case festival
        case shopping
        case lodging
        case activity
        case culture
    }

    let id: String
    let latitude: Double
    let longitude: Double
    let kind: Kind
    let isSelected: Bool
    let isHighlighted: Bool
    let isUserLocation: Bool

    init(
        id: String,
        latitude: Double,
        longitude: Double,
        kind: Kind = .attraction,
        isSelected: Bool,
        isHighlighted: Bool = false,
        isUserLocation: Bool = false
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.isUserLocation = isUserLocation
    }

    var mapPoint: MapPoint {
        MapPoint(longitude: longitude, latitude: latitude)
    }
}

struct KakaoMapView: UIViewRepresentable {
    @Binding var camera: KakaoMapCamera
    var markers: [KakaoMapMarker] = []
    var onVisibleBoundsChanged: (KakaoMapVisibleBounds) -> Void = { _ in }

    func makeUIView(context: Context) -> KMViewContainer {
        let view = KMViewContainer(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.createController(view)
        context.coordinator.controller?.prepareEngine()
        return view
    }

    func updateUIView(_ uiView: KMViewContainer, context: Context) {
        context.coordinator.onCameraChanged = { camera = $0 }
        context.coordinator.onVisibleBoundsChanged = onVisibleBoundsChanged
        context.coordinator.markers = markers
        context.coordinator.updateViewRect(uiView.bounds)
        if context.coordinator.controller?.isEngineActive == false {
            context.coordinator.controller?.activateEngine()
        }
        context.coordinator.moveCameraIfNeeded(camera)
        context.coordinator.syncMarkersIfPossible()
    }

    static func dismantleUIView(_ uiView: KMViewContainer, coordinator: Coordinator) {
        coordinator.controller?.pauseEngine()
        coordinator.controller?.resetEngine()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(camera: camera, markers: markers, onCameraChanged: { camera = $0 }, onVisibleBoundsChanged: onVisibleBoundsChanged)
    }

    final class Coordinator: NSObject, MapControllerDelegate, KakaoMapEventDelegate {
        private enum Constants {
            static let viewName = "pero-map"
            static let layerID = "pero-native-marker-layer"
            static let userLocationStyleID = "pero-native-marker-user-location"
        }

        var controller: KMController?
        var camera: KakaoMapCamera
        var markers: [KakaoMapMarker]
        var onCameraChanged: (KakaoMapCamera) -> Void
        var onVisibleBoundsChanged: (KakaoMapVisibleBounds) -> Void
        private var didAddView = false
        private var didMoveInitialCamera = false
        private var didRegisterMarkerStyles = false
        private var lastSyncedMarkers: [KakaoMapMarker] = []
        private var lastReportedVisibleBounds: KakaoMapVisibleBounds?
        private var currentViewSize: CGSize = .zero

        init(
            camera: KakaoMapCamera,
            markers: [KakaoMapMarker],
            onCameraChanged: @escaping (KakaoMapCamera) -> Void,
            onVisibleBoundsChanged: @escaping (KakaoMapVisibleBounds) -> Void
        ) {
            self.camera = camera
            self.markers = markers
            self.onCameraChanged = onCameraChanged
            self.onVisibleBoundsChanged = onVisibleBoundsChanged
            super.init()
        }

        func createController(_ view: KMViewContainer) {
            controller = KMController(viewContainer: view)
            controller?.delegate = self
        }

        func addViews() {
            guard !didAddView else { return }
            didAddView = true
            let position = MapPoint(longitude: camera.longitude, latitude: camera.latitude)
            let info = MapviewInfo(
                viewName: Constants.viewName,
                appName: "openmap",
                viewInfoName: "map",
                defaultPosition: position,
                defaultLevel: camera.level
            )
            #if DEBUG
            print("Kakao map addView requested: openmap/map")
            #endif
            if currentViewSize.width > 0, currentViewSize.height > 0 {
                controller?.addView(info, viewSize: currentViewSize)
            } else {
                controller?.addView(info)
            }
        }

        func addViewSucceeded(_ viewName: String, viewInfoName: String) {
            #if DEBUG
            print("Kakao map view succeeded: \(viewName), \(viewInfoName)")
            #endif
            if let mapView = controller?.getView(Constants.viewName) as? KakaoMap {
                mapView.eventDelegate = self
            }
            moveCameraIfNeeded(camera, force: true)
            syncCameraFromMapIfPossible()
            syncVisibleBoundsIfPossible()
            syncMarkersIfPossible(force: true)
        }

        func addViewFailed(_ viewName: String, viewInfoName: String) {
            print("Kakao map view failed: \(viewName), \(viewInfoName)")
        }

        func containerDidResized(_ size: CGSize) {
            updateViewRect(CGRect(origin: .zero, size: size))
            if !didMoveInitialCamera {
                moveCameraIfNeeded(camera, force: true)
                syncVisibleBoundsIfPossible()
                didMoveInitialCamera = true
            }
        }

        func updateViewRect(_ rect: CGRect) {
            guard rect.width > 0, rect.height > 0 else { return }
            currentViewSize = rect.size
            let mapView = controller?.getView(Constants.viewName) as? KakaoMap
            mapView?.viewRect = rect
        }

        func authenticationSucceeded() {
            #if DEBUG
            print("Kakao map auth succeeded")
            #endif
            addViews()
        }

        func authenticationFailed(_ errorCode: Int, desc: String) {
            print("Kakao map auth failed: \(errorCode), \(desc)")
        }

        func moveCameraIfNeeded(_ nextCamera: KakaoMapCamera, force: Bool = false) {
            guard force || nextCamera != camera else { return }
            guard let mapView = controller?.getView(Constants.viewName) as? KakaoMap else {
                camera = nextCamera
                return
            }
            camera = nextCamera
            let target = MapPoint(longitude: nextCamera.longitude, latitude: nextCamera.latitude)
            let update = CameraUpdate.make(target: target, zoomLevel: nextCamera.level, mapView: mapView)
            if force {
                mapView.moveCamera(update) { [weak self] in
                    self?.syncVisibleBoundsIfPossible()
                }
            } else {
                let options = CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 160)
                mapView.animateCamera(cameraUpdate: update, options: options) { [weak self] in
                    self?.syncCameraFromMapIfPossible()
                    self?.syncVisibleBoundsIfPossible()
                }
            }
        }

        func cameraDidStopped(kakaoMap: KakaoMap, by: MoveBy) {
            syncCamera(from: kakaoMap)
            syncVisibleBounds(from: kakaoMap)
        }

        private func syncCameraFromMapIfPossible() {
            guard let mapView = controller?.getView(Constants.viewName) as? KakaoMap else { return }
            syncCamera(from: mapView)
        }

        private func syncCamera(from mapView: KakaoMap) {
            let center = mapView.getPosition(CGPoint(x: currentViewSize.width / 2, y: currentViewSize.height / 2)).wgsCoord
            let nextCamera = KakaoMapCamera(latitude: center.latitude, longitude: center.longitude, level: mapView.zoomLevel)
            guard nextCamera != camera else { return }
            camera = nextCamera
            onCameraChanged(nextCamera)
        }

        private func syncVisibleBoundsIfPossible() {
            guard let mapView = controller?.getView(Constants.viewName) as? KakaoMap else { return }
            syncVisibleBounds(from: mapView)
        }

        private func syncVisibleBounds(from mapView: KakaoMap) {
            guard currentViewSize.width > 0, currentViewSize.height > 0 else { return }
            let points = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: currentViewSize.width, y: 0),
                CGPoint(x: 0, y: currentViewSize.height),
                CGPoint(x: currentViewSize.width, y: currentViewSize.height)
            ]
            let coordinates = points.map { mapView.getPosition($0).wgsCoord }
            let latitudes = coordinates.map(\.latitude)
            let longitudes = coordinates.map(\.longitude)
            guard let minLatitude = latitudes.min(),
                  let maxLatitude = latitudes.max(),
                  let minLongitude = longitudes.min(),
                  let maxLongitude = longitudes.max() else { return }
            let bounds = KakaoMapVisibleBounds(
                minLatitude: minLatitude,
                maxLatitude: maxLatitude,
                minLongitude: minLongitude,
                maxLongitude: maxLongitude
            )
            guard shouldReportVisibleBounds(bounds) else { return }
            lastReportedVisibleBounds = bounds
            onVisibleBoundsChanged(bounds)
        }

        private func shouldReportVisibleBounds(_ next: KakaoMapVisibleBounds) -> Bool {
            guard let previous = lastReportedVisibleBounds else { return true }
            let coordinateTolerance = 0.0008
            let spanTolerance = 0.0012
            return abs(next.minLatitude - previous.minLatitude) > coordinateTolerance
                || abs(next.maxLatitude - previous.maxLatitude) > coordinateTolerance
                || abs(next.minLongitude - previous.minLongitude) > coordinateTolerance
                || abs(next.maxLongitude - previous.maxLongitude) > coordinateTolerance
                || abs(next.latitudeSpan - previous.latitudeSpan) > spanTolerance
                || abs(next.longitudeSpan - previous.longitudeSpan) > spanTolerance
        }

        func syncMarkersIfPossible(force: Bool = false) {
            guard force || markers != lastSyncedMarkers else { return }
            guard let mapView = controller?.getView(Constants.viewName) as? KakaoMap else { return }
            let manager = mapView.getLabelManager()
            registerMarkerStylesIfNeeded(manager: manager)
            let layer = manager.getLabelLayer(layerID: Constants.layerID) ?? createMarkerLayer(manager: manager)
            guard let layer else { return }

            layer.clearAllItems()
            markers.forEach { marker in
                let options = PoiOptions(
                    styleID: styleID(for: marker),
                    poiID: marker.id
                )
                options.rank = marker.isUserLocation ? 1200 : (marker.isSelected ? 1100 : (marker.isHighlighted ? 900 : 1))
                options.clickable = false
                let poi = layer.addPoi(option: options, at: marker.mapPoint)
                poi?.show()
            }
            lastSyncedMarkers = markers
        }

        private func createMarkerLayer(manager: LabelManager) -> LabelLayer? {
            let option = LabelLayerOptions(
                layerID: Constants.layerID,
                competitionType: .none,
                competitionUnit: .symbolFirst,
                orderType: .rank,
                zOrder: 10
            )
            let layer = manager.addLabelLayer(option: option)
            layer?.setClickable(false)
            return layer
        }

        private func registerMarkerStylesIfNeeded(manager: LabelManager) {
            guard !didRegisterMarkerStyles else { return }
            for kind in KakaoMapMarker.Kind.allCases {
                manager.addPoiStyle(markerStyle(id: styleID(kind: kind, selected: false, highlighted: false), kind: kind, selected: false, highlighted: false))
                manager.addPoiStyle(markerStyle(id: styleID(kind: kind, selected: true, highlighted: false), kind: kind, selected: true, highlighted: false))
                manager.addPoiStyle(markerStyle(id: styleID(kind: kind, selected: false, highlighted: true), kind: kind, selected: false, highlighted: true))
            }
            manager.addPoiStyle(userLocationStyle(id: Constants.userLocationStyleID))
            didRegisterMarkerStyles = true
        }

        private func styleID(for marker: KakaoMapMarker) -> String {
            if marker.isUserLocation { return Constants.userLocationStyleID }
            return styleID(kind: marker.kind, selected: marker.isSelected, highlighted: marker.isHighlighted)
        }

        private func styleID(kind: KakaoMapMarker.Kind, selected: Bool, highlighted: Bool) -> String {
            let state = selected ? "selected" : (highlighted ? "highlighted" : "regular")
            return "pero-native-marker-\(kind.rawValue)-\(state)"
        }

        private func markerStyle(id: String, kind: KakaoMapMarker.Kind, selected: Bool, highlighted: Bool) -> PoiStyle {
            let iconStyle = PoiIconStyle(
                symbol: Self.markerImage(kind: kind, selected: selected, highlighted: highlighted),
                anchorPoint: CGPoint(x: 0.5, y: 1.0),
                enableEntranceTransition: false,
                enableExitTransition: false
            )
            return PoiStyle(styleID: id, styles: [PerLevelPoiStyle(iconStyle: iconStyle, level: 0)])
        }

        private func userLocationStyle(id: String) -> PoiStyle {
            let iconStyle = PoiIconStyle(
                symbol: Self.userLocationImage(),
                anchorPoint: CGPoint(x: 0.5, y: 0.5),
                enableEntranceTransition: true,
                enableExitTransition: true
            )
            return PoiStyle(styleID: id, styles: [PerLevelPoiStyle(iconStyle: iconStyle, level: 0)])
        }

        private static func markerImage(kind: KakaoMapMarker.Kind, selected: Bool, highlighted: Bool = false) -> UIImage {
            if let assetImage = UIImage(named: markerAssetName(kind: kind)) {
                return composedMarkerImage(assetImage: assetImage, kind: kind, selected: selected, highlighted: highlighted)
            }
            let size = CGSize(width: selected ? 32 : (highlighted ? 29 : 24), height: selected ? 40 : (highlighted ? 36 : 30))
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let cgContext = context.cgContext
                let scale = min(size.width / 42, size.height / 50)
                let bodyWidth = 30 * scale
                let bodyHeight = 30 * scale
                let bodyRect = CGRect(
                    x: (size.width - bodyWidth) / 2,
                    y: selected ? 3 : 4,
                    width: bodyWidth,
                    height: bodyHeight
                )
                let tip = CGPoint(x: size.width / 2, y: size.height - (selected ? 5 : 4))
                let bodyCenter = CGPoint(x: bodyRect.midX, y: bodyRect.midY)
                let fillColor = markerFillColor(kind: kind, selected: selected, highlighted: highlighted)
                let strokeColor: UIColor = selected || highlighted
                    ? UIColor.white
                    : markerStrokeColor(kind: kind)

                let shadowRect = CGRect(x: size.width / 2 - 8 * scale, y: size.height - 7 * scale, width: 16 * scale, height: 5 * scale)
                UIColor.black.withAlphaComponent(selected ? 0.22 : (highlighted ? 0.20 : 0.15)).setFill()
                UIBezierPath(ovalIn: shadowRect).fill()

                let pinPath = UIBezierPath(arcCenter: bodyCenter, radius: bodyWidth / 2, startAngle: .pi * 0.88, endAngle: .pi * 2.12, clockwise: true)
                pinPath.addQuadCurve(to: tip, controlPoint: CGPoint(x: bodyRect.maxX + 1.5 * scale, y: bodyRect.maxY + 9 * scale))
                pinPath.addQuadCurve(to: CGPoint(x: bodyCenter.x - bodyWidth / 2 * cos(.pi * 0.12), y: bodyCenter.y + bodyHeight / 2 * sin(.pi * 0.12)), controlPoint: CGPoint(x: bodyRect.minX - 1.5 * scale, y: bodyRect.maxY + 9 * scale))
                pinPath.close()

                cgContext.setShadow(offset: CGSize(width: 0, height: selected ? 5 : (highlighted ? 4 : 3)), blur: selected ? 10 : (highlighted ? 9 : 6), color: UIColor.black.withAlphaComponent(selected ? 0.28 : (highlighted ? 0.25 : 0.20)).cgColor)
                fillColor.setFill()
                pinPath.fill()
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)

                strokeColor.setStroke()
                pinPath.lineWidth = selected ? 3 : (highlighted ? 2.6 : 2)
                pinPath.stroke()

                UIColor.white.withAlphaComponent(selected ? 0.95 : 0.92).setFill()
                UIBezierPath(ovalIn: bodyRect.insetBy(dx: selected ? 8 : 6, dy: selected ? 8 : 6)).fill()
                if let symbol = UIImage(systemName: markerSymbolName(kind: kind)) {
                    let symbolInset = selected ? 9.5 * scale : 7.5 * scale
                    let symbolRect = bodyRect.insetBy(dx: symbolInset, dy: symbolInset)
                    let configuration = UIImage.SymbolConfiguration(pointSize: symbolRect.height, weight: .bold)
                    let configured = symbol.withConfiguration(configuration).withTintColor(fillColor, renderingMode: .alwaysOriginal)
                    configured.draw(in: symbolRect)
                } else {
                    fillColor.withAlphaComponent(selected ? 0.92 : 0.85).setFill()
                    UIBezierPath(ovalIn: bodyRect.insetBy(dx: selected ? 12 : 9, dy: selected ? 12 : 9)).fill()
                }

                if selected || highlighted {
                    UIColor.white.withAlphaComponent(0.34).setStroke()
                    let shine = UIBezierPath()
                    shine.move(to: CGPoint(x: bodyRect.minX + 9, y: bodyRect.minY + 8))
                    shine.addQuadCurve(to: CGPoint(x: bodyRect.midX + 2, y: bodyRect.minY + 5), controlPoint: CGPoint(x: bodyRect.minX + 14, y: bodyRect.minY + 3))
                    shine.lineWidth = 2
                    shine.lineCapStyle = .round
                    shine.stroke()
                }
            }
        }

        private static func composedMarkerImage(assetImage: UIImage, kind: KakaoMapMarker.Kind, selected: Bool, highlighted: Bool) -> UIImage {
            let size = CGSize(width: selected ? 32 : (highlighted ? 29 : 24), height: selected ? 40 : (highlighted ? 36 : 30))
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let cgContext = context.cgContext
                let shadowRect = CGRect(x: size.width / 2 - 6, y: size.height - 5, width: 12, height: 4)
                UIColor.black.withAlphaComponent(selected ? 0.22 : (highlighted ? 0.20 : 0.15)).setFill()
                UIBezierPath(ovalIn: shadowRect).fill()

                if selected || highlighted {
                    let ringRect = CGRect(x: 1.2, y: 1.2, width: size.width - 2.4, height: size.height - 3)
                    cgContext.setShadow(offset: CGSize(width: 0, height: selected ? 4 : 3), blur: selected ? 8 : 6, color: UIColor.black.withAlphaComponent(0.24).cgColor)
                    UIColor.white.setStroke()
                    let ringPath = UIBezierPath(roundedRect: ringRect, cornerRadius: size.width / 2)
                    ringPath.lineWidth = selected ? 2.2 : 1.8
                    ringPath.stroke()
                    cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                }

                let imageRect = CGRect(
                    x: (size.width - assetImage.size.width) / 2,
                    y: selected ? 2 : 3,
                    width: assetImage.size.width,
                    height: assetImage.size.height
                )
                let scale = min((size.width - 2) / imageRect.width, (size.height - 4) / imageRect.height)
                let scaledRect = CGRect(
                    x: (size.width - imageRect.width * scale) / 2,
                    y: selected ? 2 : 3,
                    width: imageRect.width * scale,
                    height: imageRect.height * scale
                )
                assetImage.draw(in: scaledRect)

                if highlighted {
                    markerFillColor(kind: kind, selected: false, highlighted: true).withAlphaComponent(0.18).setFill()
                    UIBezierPath(ovalIn: CGRect(x: 7, y: 7, width: size.width - 14, height: size.width - 14)).fill(with: .plusDarker, alpha: 0.18)
                }
            }
        }

        private static func markerAssetName(kind: KakaoMapMarker.Kind) -> String {
            "pero-dice-marker"
        }

        private static func markerFillColor(kind: KakaoMapMarker.Kind, selected: Bool, highlighted: Bool) -> UIColor {
            if selected {
                return UIColor(red: 1.0, green: 0.48, blue: 0.18, alpha: 1)
            }
            if highlighted {
                return UIColor(red: 1.0, green: 0.80, blue: 0.18, alpha: 1)
            }
            switch kind {
            case .attraction:
                return UIColor(red: 0.11, green: 0.41, blue: 0.72, alpha: 1)
            case .restaurant:
                return UIColor(red: 0.88, green: 0.20, blue: 0.17, alpha: 1)
            case .festival:
                return UIColor(red: 0.58, green: 0.23, blue: 0.88, alpha: 1)
            case .shopping:
                return UIColor(red: 0.84, green: 0.46, blue: 0.07, alpha: 1)
            case .lodging:
                return UIColor(red: 0.20, green: 0.33, blue: 0.70, alpha: 1)
            case .activity:
                return UIColor(red: 0.05, green: 0.55, blue: 0.38, alpha: 1)
            case .culture:
                return UIColor(red: 0.20, green: 0.47, blue: 0.48, alpha: 1)
            }
        }

        private static func markerStrokeColor(kind: KakaoMapMarker.Kind) -> UIColor {
            markerFillColor(kind: kind, selected: false, highlighted: false).withAlphaComponent(0.88)
        }

        private static func markerSymbolName(kind: KakaoMapMarker.Kind) -> String {
            switch kind {
            case .attraction:
                return "mappin.and.ellipse"
            case .restaurant:
                return "fork.knife"
            case .festival:
                return "sparkles"
            case .shopping:
                return "bag.fill"
            case .lodging:
                return "bed.double.fill"
            case .activity:
                return "figure.run"
            case .culture:
                return "building.columns.fill"
            }
        }

        private static func userLocationImage() -> UIImage {
            let size = CGSize(width: 38, height: 38)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let cgContext = context.cgContext
                let outerRect = CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5)
                UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.18).setFill()
                UIBezierPath(ovalIn: outerRect).fill()

                let ringRect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
                cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.18).cgColor)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: ringRect).fill()
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1).setFill()
                UIBezierPath(ovalIn: ringRect.insetBy(dx: 4, dy: 4)).fill()
            }
        }
    }
}

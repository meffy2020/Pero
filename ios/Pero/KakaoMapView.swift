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
    let id: String
    let latitude: Double
    let longitude: Double
    let isSelected: Bool
    let isUserLocation: Bool

    init(
        id: String,
        latitude: Double,
        longitude: Double,
        isSelected: Bool,
        isUserLocation: Bool = false
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.isSelected = isSelected
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
            static let regularStyleID = "pero-native-marker-regular"
            static let selectedStyleID = "pero-native-marker-selected"
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
                options.rank = marker.isUserLocation ? 1200 : (marker.isSelected ? 1000 : 1)
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
            manager.addPoiStyle(markerStyle(id: Constants.regularStyleID, selected: false))
            manager.addPoiStyle(markerStyle(id: Constants.selectedStyleID, selected: true))
            manager.addPoiStyle(userLocationStyle(id: Constants.userLocationStyleID))
            didRegisterMarkerStyles = true
        }

        private func styleID(for marker: KakaoMapMarker) -> String {
            if marker.isUserLocation { return Constants.userLocationStyleID }
            return marker.isSelected ? Constants.selectedStyleID : Constants.regularStyleID
        }

        private func markerStyle(id: String, selected: Bool) -> PoiStyle {
            let iconStyle = PoiIconStyle(
                symbol: Self.markerImage(selected: selected),
                anchorPoint: CGPoint(x: 0.5, y: 0.5),
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

        private static func markerImage(selected: Bool) -> UIImage {
            let size = CGSize(width: selected ? 34 : 18, height: selected ? 34 : 18)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: selected ? 3 : 2, dy: selected ? 3 : 2)
                let cgContext = context.cgContext
                cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: selected ? 5 : 3, color: UIColor.black.withAlphaComponent(0.18).cgColor)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: rect).fill()
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                let innerInset = selected ? CGFloat(8) : CGFloat(5)
                UIColor(red: 0.13, green: 0.13, blue: 0.12, alpha: 1).setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: innerInset, dy: innerInset)).fill()
                if selected {
                    UIColor(red: 0.82, green: 0.54, blue: 0.18, alpha: 1).setStroke()
                    let strokePath = UIBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
                    strokePath.lineWidth = 3
                    strokePath.stroke()
                }
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

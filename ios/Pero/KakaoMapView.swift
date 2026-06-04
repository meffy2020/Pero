import SwiftUI
import UIKit
import KakaoMapsSDK

struct KakaoMapCamera: Equatable {
    var latitude: Double
    var longitude: Double
    var level: Int

    static let seoul = KakaoMapCamera(latitude: 37.5665, longitude: 126.9780, level: 8)
}

struct KakaoMapMarker: Equatable, Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let isSelected: Bool

    var mapPoint: MapPoint {
        MapPoint(longitude: longitude, latitude: latitude)
    }
}

struct KakaoMapView: UIViewRepresentable {
    let camera: KakaoMapCamera
    var markers: [KakaoMapMarker] = []

    func makeUIView(context: Context) -> KMViewContainer {
        let view = KMViewContainer(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.createController(view)
        context.coordinator.controller?.prepareEngine()
        return view
    }

    func updateUIView(_ uiView: KMViewContainer, context: Context) {
        context.coordinator.camera = camera
        context.coordinator.markers = markers
        context.coordinator.updateViewRect(uiView.bounds)
        if context.coordinator.controller?.isEngineActive == false {
            context.coordinator.controller?.activateEngine()
        }
        context.coordinator.moveCameraIfPossible()
        context.coordinator.syncMarkersIfPossible()
    }

    static func dismantleUIView(_ uiView: KMViewContainer, coordinator: Coordinator) {
        coordinator.controller?.pauseEngine()
        coordinator.controller?.resetEngine()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(camera: camera, markers: markers)
    }

    final class Coordinator: NSObject, MapControllerDelegate {
        private enum Constants {
            static let viewName = "pero-map"
            static let layerID = "pero-native-marker-layer"
            static let regularStyleID = "pero-native-marker-regular"
            static let selectedStyleID = "pero-native-marker-selected"
        }

        var controller: KMController?
        var camera: KakaoMapCamera
        var markers: [KakaoMapMarker]
        private var didAddView = false
        private var didMoveInitialCamera = false
        private var didRegisterMarkerStyles = false
        private var lastSyncedMarkers: [KakaoMapMarker] = []
        private var currentViewSize: CGSize = .zero

        init(camera: KakaoMapCamera, markers: [KakaoMapMarker]) {
            self.camera = camera
            self.markers = markers
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
            moveCameraIfPossible()
            syncMarkersIfPossible(force: true)
        }

        func addViewFailed(_ viewName: String, viewInfoName: String) {
            print("Kakao map view failed: \(viewName), \(viewInfoName)")
        }

        func containerDidResized(_ size: CGSize) {
            updateViewRect(CGRect(origin: .zero, size: size))
            if !didMoveInitialCamera {
                moveCameraIfPossible()
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

        func moveCameraIfPossible() {
            guard let mapView = controller?.getView(Constants.viewName) as? KakaoMap else { return }
            let target = MapPoint(longitude: camera.longitude, latitude: camera.latitude)
            let update = CameraUpdate.make(target: target, zoomLevel: camera.level, mapView: mapView)
            mapView.moveCamera(update)
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
                    styleID: marker.isSelected ? Constants.selectedStyleID : Constants.regularStyleID,
                    poiID: marker.id
                )
                options.rank = marker.isSelected ? 1000 : 1
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
            didRegisterMarkerStyles = true
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
    }
}

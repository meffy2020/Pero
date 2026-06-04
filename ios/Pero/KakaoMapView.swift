import SwiftUI
import CoreLocation
import KakaoMapsSDK

struct KakaoMapCamera: Equatable {
    var latitude: Double
    var longitude: Double
    var level: Int

    static let seoul = KakaoMapCamera(latitude: 37.5665, longitude: 126.9780, level: 8)
}

struct KakaoMapView: UIViewRepresentable {
    let camera: KakaoMapCamera

    func makeUIView(context: Context) -> KMViewContainer {
        let view = KMViewContainer(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.createController(view)
        context.coordinator.controller?.prepareEngine()
        return view
    }

    func updateUIView(_ uiView: KMViewContainer, context: Context) {
        context.coordinator.camera = camera
        context.coordinator.updateViewRect(uiView.bounds)
        if context.coordinator.controller?.isEngineActive == false {
            context.coordinator.controller?.activateEngine()
        }
        context.coordinator.moveCameraIfPossible()
    }

    static func dismantleUIView(_ uiView: KMViewContainer, coordinator: Coordinator) {
        coordinator.controller?.pauseEngine()
        coordinator.controller?.resetEngine()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(camera: camera)
    }

    final class Coordinator: NSObject, MapControllerDelegate {
        var controller: KMController?
        var camera: KakaoMapCamera
        private var didAddView = false
        private var didMoveInitialCamera = false
        private var currentViewSize: CGSize = .zero

        init(camera: KakaoMapCamera) {
            self.camera = camera
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
                viewName: "pero-map",
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
            let mapView = controller?.getView("pero-map") as? KakaoMap
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
            guard let mapView = controller?.getView("pero-map") as? KakaoMap else { return }
            let target = MapPoint(longitude: camera.longitude, latitude: camera.latitude)
            let update = CameraUpdate.make(target: target, zoomLevel: camera.level, mapView: mapView)
            mapView.moveCamera(update)
        }
    }
}

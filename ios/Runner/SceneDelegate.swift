import UIKit
import Flutter

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let phoneWindow = UIWindow(windowScene: windowScene)
        let controller = FlutterViewController(
            engine: flutterEngine,
            nibName: nil,
            bundle: nil
        )
        controller.loadDefaultSplashScreenView()
        phoneWindow.rootViewController = controller
        window = phoneWindow
        phoneWindow.makeKeyAndVisible()
    }
}


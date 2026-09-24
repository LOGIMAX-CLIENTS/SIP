import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyOverlays: [UIView] = []

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    showPrivacyOverlay(for: scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    showPrivacyOverlay(for: scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    hidePrivacyOverlay()
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    hidePrivacyOverlay()
  }

  private func showPrivacyOverlay(for scene: UIScene? = nil) {
    hidePrivacyOverlay()

    let scenes = UIApplication.shared.connectedScenes
    for s in scenes {
      guard let windowScene = s as? UIWindowScene else { continue }
      for window in windowScene.windows {
        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = .black
        overlay.tag = 99999
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        window.addSubview(overlay)
        window.bringSubviewToFront(overlay)
        privacyOverlays.append(overlay)
      }
    }
  }

  private func hidePrivacyOverlay() {
    for overlay in privacyOverlays {
      overlay.removeFromSuperview()
    }
    privacyOverlays.removeAll()

    for s in UIApplication.shared.connectedScenes {
      guard let windowScene = s as? UIWindowScene else { continue }
      for window in windowScene.windows {
        while let view = window.viewWithTag(99999) {
          view.removeFromSuperview()
        }
      }
    }
  }
}

import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyOverlays: [UIView] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func handleWillResignActive() {
    showPrivacyOverlay()
  }

  @objc private func handleDidEnterBackground() {
    showPrivacyOverlay()
  }

  @objc private func handleDidBecomeActive() {
    hidePrivacyOverlay()
  }

  @objc private func handleWillEnterForeground() {
    hidePrivacyOverlay()
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    showPrivacyOverlay()
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    showPrivacyOverlay()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    hidePrivacyOverlay()
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    hidePrivacyOverlay()
  }

  private func showPrivacyOverlay() {
    hidePrivacyOverlay()
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
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
    if privacyOverlays.isEmpty, let window = self.window {
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

  private func hidePrivacyOverlay() {
    for overlay in privacyOverlays {
      overlay.removeFromSuperview()
    }
    privacyOverlays.removeAll()

    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        while let view = window.viewWithTag(99999) {
          view.removeFromSuperview()
        }
      }
    }
    self.window?.viewWithTag(99999)?.removeFromSuperview()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[APNs] Failed to register for remote notifications: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}

import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
      try session.setActive(true)
    } catch {
      print("Failed to configure audio session: \(error)")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // iOS 27 only launches apps that use the UIScene lifecycle. Under it the
  // Flutter engine is created by the storyboard's view controller rather than
  // at launch, so plugins are registered here once that engine exists.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

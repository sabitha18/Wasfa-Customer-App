import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by google_maps_flutter on iOS — without it the Track order
    // map crashes. This is the same key as AndroidManifest.xml; if the map
    // is blank on iPhone, the key is restricted to Android only — replace it
    // with an iOS key (Google Cloud → "Maps SDK for iOS" enabled).
    GMSServices.provideAPIKey("AIzaSyCSjYdB26Vz43Oca337B6TQF6DrXIwMKAU")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

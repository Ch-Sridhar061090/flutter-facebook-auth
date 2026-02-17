import Flutter
import UIKit
import FBSDKCoreKit

@objc public class SwiftFlutterFacebookAuthPlugin: NSObject, FlutterPlugin {
  let facebookAuth = FacebookAuth()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "app.meedu/flutter_facebook_auth", binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterFacebookAuthPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    facebookAuth.handle(call: call, result: result)
  }

  // MARK: - Handle Facebook App / Deep Links

  // For modern FB SDK: handle via continue userActivity (universal links, etc.)
  @objc public func application(_ application: UIApplication,
                          continue userActivity: NSUserActivity,
                          restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    let handled = ApplicationDelegate.shared.application(application,
                                                         continue: userActivity,
                                                         restorationHandler: restorationHandler)
    return handled
  }

  // Keep the classic open URL handler (for custom scheme fbXXXX://)
  @objc public func application(_ app: UIApplication,
                          open url: URL,
                          options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    let sourceApplication = options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String
    let annotation = options[UIApplication.OpenURLOptionsKey.annotation]

    let handled = ApplicationDelegate.shared.application(app,
                                                         open: url,
                                                         sourceApplication: sourceApplication,
                                                         annotation: annotation)
    return handled
  }
}
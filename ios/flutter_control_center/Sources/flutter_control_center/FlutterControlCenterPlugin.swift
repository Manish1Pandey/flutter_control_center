import Flutter
import UIKit
import WidgetKit

/// Flutter plugin side of flutter_control_center: owns control state in the App Group,
/// reloads controls, and forwards control actions (deep links, Darwin notifications and the
/// App Group queue) to Dart.
public final class FlutterControlCenterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
  FlutterSceneLifeCycleDelegate
{
  static let methodChannelName = "flutter_control_center"
  static let eventChannelName = "flutter_control_center/actions"
  /// `UserDefaults.standard` key remembering the configured App Group across launches.
  static let persistedAppGroupKey = "flutter_control_center.appGroup"
  /// Optional Info.plist key providing a default App Group before Dart calls `configure`.
  static let infoPlistAppGroupKey = "FlutterControlCenterAppGroup"
  /// How many delivered action ids are remembered to suppress duplicates.
  static let deliveredIdMemory = 200

  private var store: FlutterControlCenterStore?
  private var eventSink: FlutterEventSink?
  private var bufferedEvents: [[String: Any]] = []
  private var deliveredIds: [String] = []
  private var observedNotificationName: String?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterControlCenterPlugin()
    let channel = FlutterMethodChannel(
      name: methodChannelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(
      name: eventChannelName, binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
    instance.restoreConfiguration()
  }

  deinit {
    stopObservingDarwinNotification()
  }

  // MARK: - Configuration

  private func restoreConfiguration() {
    let persisted = UserDefaults.standard.string(forKey: Self.persistedAppGroupKey)
    let fromPlist = Bundle.main.object(forInfoDictionaryKey: Self.infoPlistAppGroupKey) as? String
    if let group = persisted ?? fromPlist, let store = FlutterControlCenterStore(appGroup: group) {
      activate(store: store)
    }
  }

  private func activate(store: FlutterControlCenterStore) {
    self.store = store
    startObservingDarwinNotification(appGroup: store.appGroup)
  }

  private static var isSupportedOS: Bool {
    if #available(iOS 18.0, *) {
      return true
    }
    return false
  }

  // MARK: - Method channel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "isSupported" {
      result(Self.isSupportedOS)
      return
    }
    guard #available(iOS 18.0, *) else {
      result(
        FlutterError(
          code: "unsupported",
          message: "Controls require iOS 18 or later (running \(UIDevice.current.systemVersion)).",
          details: nil))
      return
    }
    switch call.method {
    case "configure":
      configure(args: args, result: result)
    case "setToggleState":
      guard let store = requireStore(result), let kind = requireKind(args, result) else { return }
      guard let isOn = args["isOn"] as? Bool else {
        result(FlutterError(code: "invalid_argument", message: "isOn must be a bool.", details: nil))
        return
      }
      store.setToggle(kind: kind, isOn: isOn, source: FlutterControlCenterStore.sourceApp)
      if args["reload"] as? Bool ?? true {
        ControlCenter.shared.reloadControls(ofKind: kind)
      }
      result(nil)
    case "getState":
      guard let store = requireStore(result), let kind = requireKind(args, result) else { return }
      result(store.state(kind: kind))
    case "getAllStates":
      guard let store = requireStore(result) else { return }
      result(store.allStates())
    case "clearState":
      guard let store = requireStore(result), let kind = requireKind(args, result) else { return }
      store.removeState(kind: kind)
      if args["reload"] as? Bool ?? true {
        ControlCenter.shared.reloadControls(ofKind: kind)
      }
      result(nil)
    case "reloadControls":
      guard let kind = requireKind(args, result) else { return }
      ControlCenter.shared.reloadControls(ofKind: kind)
      result(nil)
    case "reloadAllControls":
      ControlCenter.shared.reloadAllControls()
      result(nil)
    case "getInstalledControls":
      Task {
        do {
          let controls = try await ControlCenter.shared.currentControls()
          let kinds = Array(Set(controls.map { $0.kind })).sorted()
          await MainActor.run { result(kinds) }
        } catch {
          await MainActor.run {
            result(
              FlutterError(
                code: "native_error", message: "currentControls() failed: \(error)", details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configure(args: [String: Any], result: @escaping FlutterResult) {
    guard let group = args["appGroup"] as? String, group.hasPrefix("group."), group.count > 6
    else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "appGroup must be an App Group identifier such as 'group.com.example.app'.",
          details: nil))
      return
    }
    guard let store = FlutterControlCenterStore(appGroup: group) else {
      result(
        FlutterError(
          code: "app_group_unavailable",
          message: "UserDefaults(suiteName: \"\(group)\") could not be created.", details: nil))
      return
    }
    guard store.isAppGroupAccessible else {
      result(
        FlutterError(
          code: "app_group_unavailable",
          message:
            "The app is not entitled to App Group '\(group)'. Add it under Signing & Capabilities > App Groups for the Runner target and the Widget Extension.",
          details: nil))
      return
    }
    UserDefaults.standard.set(group, forKey: Self.persistedAppGroupKey)
    activate(store: store)
    drainQueue()
    result(nil)
  }

  private func requireStore(_ result: FlutterResult) -> FlutterControlCenterStore? {
    if let store = store {
      return store
    }
    result(
      FlutterError(
        code: "not_configured",
        message: "Call FlutterControlCenter.configure(appGroup: ...) first.", details: nil))
    return nil
  }

  private func requireKind(_ args: [String: Any], _ result: FlutterResult) -> String? {
    if let kind = args["kind"] as? String, !kind.isEmpty {
      return kind
    }
    result(
      FlutterError(code: "invalid_argument", message: "kind must be a non-empty string.", details: nil))
    return nil
  }

  // MARK: - Event channel

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    let pending = bufferedEvents
    bufferedEvents.removeAll()
    for event in pending {
      events(event)
    }
    drainQueue()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  /// Sends `action` to Dart once (dedupe on id), buffering until Dart listens.
  private func deliver(_ action: [String: Any]) {
    guard let id = action["id"] as? String, !deliveredIds.contains(id) else {
      return
    }
    deliveredIds.append(id)
    if deliveredIds.count > Self.deliveredIdMemory {
      deliveredIds.removeFirst(deliveredIds.count - Self.deliveredIdMemory)
    }
    if let sink = eventSink {
      sink(action)
    } else {
      bufferedEvents.append(action)
    }
  }

  private func drainQueue() {
    guard let store = store else { return }
    for action in store.drainActions() {
      deliver(action)
    }
  }

  @discardableResult
  private func handle(url: URL) -> Bool {
    guard let action = FlutterControlCenterStore.parseActionURL(url) else {
      return false
    }
    // The URL carries the full action; drop the queued copy so it is not delivered twice.
    if let id = action["id"] as? String {
      store?.removeAction(id: id)
    }
    deliver(action)
    drainQueue()
    return true
  }

  // MARK: - Darwin notifications

  private func startObservingDarwinNotification(appGroup: String) {
    let name = FlutterControlCenterStore.notificationName(appGroup: appGroup)
    if observedNotificationName == name { return }
    stopObservingDarwinNotification()
    observedNotificationName = name
    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      observer,
      { _, observer, _, _, _ in
        guard let observer = observer else { return }
        let plugin = Unmanaged<FlutterControlCenterPlugin>.fromOpaque(observer)
          .takeUnretainedValue()
        DispatchQueue.main.async {
          plugin.drainQueue()
        }
      },
      name as CFString,
      nil,
      .deliverImmediately
    )
  }

  private func stopObservingDarwinNotification() {
    guard let name = observedNotificationName else { return }
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      CFNotificationName(name as CFString),
      nil)
    observedNotificationName = nil
  }

  // MARK: - UIApplicationDelegate (apps without UIScene)

  public func applicationDidBecomeActive(_ application: UIApplication) {
    drainQueue()
  }

  public func application(
    _ application: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return handle(url: url)
  }

  // MARK: - FlutterSceneLifeCycleDelegate (apps using UIScene)

  public func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    var handled = false
    for context in connectionOptions?.urlContexts ?? [] {
      handled = handle(url: context.url) || handled
    }
    return handled
  }

  public func sceneDidBecomeActive(_ scene: UIScene) {
    drainQueue()
  }

  public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in URLContexts {
      handled = handle(url: context.url) || handled
    }
    return handled
  }
}

// FlutterControlCenterStore.swift
// Part of the flutter_control_center Flutter plugin.
//
// This single file is compiled into BOTH processes that take part in a control:
//   * the Flutter app (inside the flutter_control_center plugin), and
//   * the Widget Extension (copied there by `dart run flutter_control_center:setup`).
// It defines the on-disk protocol they share through an App Group, so keep the two
// copies identical: re-run the setup command after upgrading the plugin.

import Foundation

/// Shared state and action queue for iOS controls, stored in an App Group
/// `UserDefaults` suite.
///
/// Layout (version 1):
/// * `fcc.v1.state.<kind>`: `["isOn": Bool, "updatedAt": Double (ms since epoch), "source": "app" | "control"]`
/// * `fcc.v1.actions`: array of action dictionaries, oldest first, capped at ``maxQueuedActions``.
/// * Darwin notification `<appGroup>.fcc.v1.changed` is posted when the extension queues an action.
public final class FlutterControlCenterStore {
  /// Prefix of every per-control state key.
  public static let statePrefix = "fcc.v1.state."
  /// Key of the pending action queue.
  public static let actionsKey = "fcc.v1.actions"
  /// Maximum number of queued actions kept; older ones are dropped first.
  public static let maxQueuedActions = 100
  /// Host used in deep links produced by ``actionURL(scheme:action:)``.
  public static let urlHost = "flutter-control-center"
  /// Path used in deep links produced by ``actionURL(scheme:action:)``.
  public static let urlPath = "/action"
  /// Query-item prefix used for payload entries in deep links.
  public static let payloadQueryPrefix = "p."

  /// Value of `source` when the Flutter app wrote the state.
  public static let sourceApp = "app"
  /// Value of `source` when a control (the extension) wrote the state.
  public static let sourceControl = "control"
  /// Value of `type` for a button press.
  public static let typeButton = "button"
  /// Value of `type` for a toggle change.
  public static let typeToggle = "toggle"

  /// The App Group identifier this store reads and writes.
  public let appGroup: String
  private let defaults: UserDefaults

  /// Opens the store for `appGroup`. Returns `nil` when the identifier is empty or the
  /// suite cannot be created.
  public init?(appGroup: String) {
    guard !appGroup.isEmpty, let defaults = UserDefaults(suiteName: appGroup) else {
      return nil
    }
    self.appGroup = appGroup
    self.defaults = defaults
  }

  /// `true` when the running process is entitled to the App Group (the shared container
  /// exists). On a device, a missing `com.apple.security.application-groups` entitlement
  /// makes this `false` and the suite silently becomes process-local.
  public var isAppGroupAccessible: Bool {
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
  }

  /// The Darwin notification name used for `appGroup`.
  public static func notificationName(appGroup: String) -> String {
    return "\(appGroup).fcc.v1.changed"
  }

  /// Current time in milliseconds since the Unix epoch.
  public static func nowMillis() -> Double {
    return (Date().timeIntervalSince1970 * 1000).rounded()
  }

  // MARK: - State

  /// Stores the value of the toggle `kind`.
  public func setToggle(kind: String, isOn: Bool, source: String) {
    let entry: [String: Any] = [
      "isOn": isOn,
      "updatedAt": FlutterControlCenterStore.nowMillis(),
      "source": source,
    ]
    defaults.set(entry, forKey: FlutterControlCenterStore.statePrefix + kind)
  }

  /// Returns the stored state of `kind`, or `nil` when none was stored.
  public func state(kind: String) -> [String: Any]? {
    guard
      let raw = defaults.dictionary(forKey: FlutterControlCenterStore.statePrefix + kind),
      let isOn = raw["isOn"] as? Bool
    else {
      return nil
    }
    return [
      "kind": kind,
      "isOn": isOn,
      "updatedAt": (raw["updatedAt"] as? NSNumber)?.doubleValue ?? 0,
      "source": raw["source"] as? String ?? FlutterControlCenterStore.sourceApp,
    ]
  }

  /// Returns the stored value of toggle `kind`, or `defaultValue` when none was stored.
  public func isOn(kind: String, defaultValue: Bool) -> Bool {
    return state(kind: kind)?["isOn"] as? Bool ?? defaultValue
  }

  /// Returns every stored control state keyed by kind.
  public func allStates() -> [String: [String: Any]] {
    var result: [String: [String: Any]] = [:]
    for key in defaults.dictionaryRepresentation().keys
    where key.hasPrefix(FlutterControlCenterStore.statePrefix) {
      let kind = String(key.dropFirst(FlutterControlCenterStore.statePrefix.count))
      if let entry = state(kind: kind) {
        result[kind] = entry
      }
    }
    return result
  }

  /// Removes the stored state of `kind`.
  public func removeState(kind: String) {
    defaults.removeObject(forKey: FlutterControlCenterStore.statePrefix + kind)
  }

  // MARK: - Action queue

  /// Builds a well-formed action dictionary with a fresh UUID and timestamp.
  public static func makeAction(
    kind: String,
    type: String,
    action: String?,
    value: Bool?,
    payload: [String: String]
  ) -> [String: Any] {
    var entry: [String: Any] = [
      "id": UUID().uuidString,
      "kind": kind,
      "type": type,
      "payload": payload,
      "timestamp": nowMillis(),
    ]
    if let action = action {
      entry["action"] = action
    }
    if let value = value {
      entry["value"] = value
    }
    return entry
  }

  /// Appends `action` to the pending queue, dropping the oldest entries beyond
  /// ``maxQueuedActions``.
  public func enqueue(action: [String: Any]) {
    var queue = pendingActions()
    queue.append(action)
    if queue.count > FlutterControlCenterStore.maxQueuedActions {
      queue.removeFirst(queue.count - FlutterControlCenterStore.maxQueuedActions)
    }
    defaults.set(queue, forKey: FlutterControlCenterStore.actionsKey)
  }

  /// Returns the pending actions without removing them.
  public func pendingActions() -> [[String: Any]] {
    return defaults.array(forKey: FlutterControlCenterStore.actionsKey) as? [[String: Any]] ?? []
  }

  /// Returns and removes all pending actions, oldest first.
  public func drainActions() -> [[String: Any]] {
    let queue = pendingActions()
    if !queue.isEmpty {
      defaults.removeObject(forKey: FlutterControlCenterStore.actionsKey)
    }
    return queue
  }

  /// Removes the pending action with `id`, if queued.
  public func removeAction(id: String) {
    let queue = pendingActions()
    let filtered = queue.filter { ($0["id"] as? String) != id }
    if filtered.count != queue.count {
      defaults.set(filtered, forKey: FlutterControlCenterStore.actionsKey)
    }
  }

  // MARK: - Signalling

  /// Posts the Darwin notification for this App Group so a running app drains the queue.
  public func postChangeNotification() {
    let name = FlutterControlCenterStore.notificationName(appGroup: appGroup) as CFString
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(name),
      nil,
      nil,
      true
    )
  }

  // MARK: - Deep links

  /// Encodes `action` as `<scheme>://flutter-control-center/action?...`.
  public static func actionURL(scheme: String, action: [String: Any]) -> URL? {
    guard !scheme.isEmpty else {
      return nil
    }
    var components = URLComponents()
    components.scheme = scheme
    components.host = urlHost
    components.path = urlPath
    var items: [URLQueryItem] = []
    for key in ["id", "kind", "type", "action"] {
      if let value = action[key] as? String {
        items.append(URLQueryItem(name: key, value: value))
      }
    }
    if let value = action["value"] as? Bool {
      items.append(URLQueryItem(name: "value", value: value ? "true" : "false"))
    }
    if let timestamp = (action["timestamp"] as? NSNumber)?.doubleValue {
      items.append(URLQueryItem(name: "timestamp", value: String(Int64(timestamp))))
    }
    if let payload = action["payload"] as? [String: String] {
      for key in payload.keys.sorted() {
        items.append(URLQueryItem(name: payloadQueryPrefix + key, value: payload[key]))
      }
    }
    components.queryItems = items
    return components.url
  }

  /// Decodes a deep link produced by ``actionURL(scheme:action:)``. Returns `nil` for any
  /// other URL (so apps can keep handling their own deep links).
  public static func parseActionURL(_ url: URL) -> [String: Any]? {
    guard
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.host == urlHost,
      components.path == urlPath
    else {
      return nil
    }
    var entry: [String: Any] = [:]
    var payload: [String: String] = [:]
    for item in components.queryItems ?? [] {
      let value = item.value ?? ""
      if item.name.hasPrefix(payloadQueryPrefix) {
        payload[String(item.name.dropFirst(payloadQueryPrefix.count))] = value
        continue
      }
      switch item.name {
      case "id", "kind", "type", "action":
        entry[item.name] = value
      case "value":
        entry["value"] = value == "true"
      case "timestamp":
        entry["timestamp"] = Double(value) ?? nowMillis()
      default:
        break
      }
    }
    guard
      let id = entry["id"] as? String, !id.isEmpty,
      let kind = entry["kind"] as? String, !kind.isEmpty
    else {
      return nil
    }
    if entry["type"] == nil {
      entry["type"] = typeButton
    }
    if entry["timestamp"] == nil {
      entry["timestamp"] = nowMillis()
    }
    entry["payload"] = payload
    return entry
  }
}

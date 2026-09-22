// FlutterControls.swift
// Part of the flutter_control_center Flutter plugin — Widget Extension kit.
//
// Copied into your Widget Extension by `dart run flutter_control_center:setup`.
// Do not edit: re-running the setup command replaces this file. Configure your controls in
// <Extension>Bundle.swift and FlutterControlCenterConfiguration.swift instead.
//
// Requires FlutterControlCenterStore.swift (copied alongside) and a
// `FlutterControlCenterConfiguration` enum providing `appGroup` and `urlScheme`.

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Errors

/// Errors thrown by the Flutter control intents.
@available(iOS 18.0, *)
public enum FlutterControlsError: Error, CustomLocalizedStringResourceConvertible {
  /// The App Group in `FlutterControlCenterConfiguration.appGroup` cannot be opened.
  case appGroupUnavailable(String)
  /// `FlutterControlCenterConfiguration.urlScheme` cannot form a valid URL.
  case invalidURLScheme(String)

  public var localizedStringResource: LocalizedStringResource {
    switch self {
    case .appGroupUnavailable(let group):
      return "App Group \(group) is not available to the widget extension."
    case .invalidURLScheme(let scheme):
      return "URL scheme \(scheme) cannot open the app."
    }
  }
}

@available(iOS 18.0, *)
enum FlutterControlsShared {
  static func store() throws -> FlutterControlCenterStore {
    let group = FlutterControlCenterConfiguration.appGroup
    guard let store = FlutterControlCenterStore(appGroup: group) else {
      throw FlutterControlsError.appGroupUnavailable(group)
    }
    return store
  }

  static func encode(payload: [String: String]) -> String {
    guard
      let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return json
  }

  static func decode(payload json: String) -> [String: String] {
    guard
      let data = json.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
    else {
      return [:]
    }
    return object
  }
}

// MARK: - Toggle

/// Reads a toggle's value from the App Group written by the Flutter app or by
/// ``FlutterSetValueIntent``.
@available(iOS 18.0, *)
public struct FlutterToggleValueProvider: ControlValueProvider {
  /// The control kind whose value is read.
  public let kind: String
  /// Value used before anything was stored.
  public let defaultValue: Bool

  public init(kind: String, defaultValue: Bool) {
    self.kind = kind
    self.defaultValue = defaultValue
  }

  public var previewValue: Bool { defaultValue }

  public func currentValue() async throws -> Bool {
    return try FlutterControlsShared.store().isOn(kind: kind, defaultValue: defaultValue)
  }
}

/// Sets a toggle's value from Control Center / Lock Screen / Action button.
///
/// Stores the value in the App Group and, when `notifyApp` is true, queues a `toggle` action
/// and posts a Darwin notification so a running Flutter app receives it on
/// `FlutterControlCenter.actions` (a suspended app receives it when it next becomes active).
@available(iOS 18.0, *)
public struct FlutterSetValueIntent: SetValueIntent {
  public static let title: LocalizedStringResource = "Set Flutter control value"
  public static let isDiscoverable = false

  @Parameter(title: "Control kind")
  public var kind: String

  @Parameter(title: "Notify app", default: true)
  public var notifyApp: Bool

  @Parameter(title: "Value")
  public var value: Bool

  public init() {}

  public init(kind: String, notifyApp: Bool) {
    self.kind = kind
    self.notifyApp = notifyApp
  }

  public func perform() async throws -> some IntentResult {
    let store = try FlutterControlsShared.store()
    store.setToggle(kind: kind, isOn: value, source: FlutterControlCenterStore.sourceControl)
    if notifyApp {
      store.enqueue(
        action: FlutterControlCenterStore.makeAction(
          kind: kind, type: FlutterControlCenterStore.typeToggle, action: nil, value: value,
          payload: [:]))
      store.postChangeNotification()
    }
    return .result()
  }
}

/// A toggle control backed by App Group state shared with the Flutter app.
///
/// Conform a struct to it in your Widget Extension and list it in your `WidgetBundle`:
///
/// ```swift
/// struct FocusModeControl: FlutterControlToggle {
///   static let kind = "focus_mode"
///   let title = "Focus mode"
///   let systemImageOn = "moon.fill"
/// }
/// ```
@available(iOS 18.0, *)
public protocol FlutterControlToggle: ControlWidget {
  /// Unique control kind; the same string is used from Dart.
  static var kind: String { get }
  /// Title shown on the control.
  var title: String { get }
  /// SF Symbol shown when on. Defaults to `"checkmark.circle.fill"`.
  var systemImageOn: String { get }
  /// SF Symbol shown when off. Defaults to ``systemImageOn``.
  var systemImageOff: String { get }
  /// Value label shown when on. Defaults to `"On"`.
  var onLabel: String { get }
  /// Value label shown when off. Defaults to `"Off"`.
  var offLabel: String { get }
  /// Value used before the app or the control stored one. Defaults to `false`.
  var defaultValue: Bool { get }
  /// Whether flipping the control queues an action for the app. Defaults to `true`.
  var notifiesApp: Bool { get }
  /// Description shown in the controls gallery. Defaults to ``title``.
  var galleryDescription: String { get }
}

@available(iOS 18.0, *)
extension FlutterControlToggle {
  public var systemImageOn: String { "checkmark.circle.fill" }
  public var systemImageOff: String { systemImageOn }
  public var onLabel: String { "On" }
  public var offLabel: String { "Off" }
  public var defaultValue: Bool { false }
  public var notifiesApp: Bool { true }
  public var galleryDescription: String { title }

  public var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: Self.kind,
      provider: FlutterToggleValueProvider(kind: Self.kind, defaultValue: defaultValue)
    ) { isOn in
      ControlWidgetToggle(
        title,
        isOn: isOn,
        action: FlutterSetValueIntent(kind: Self.kind, notifyApp: notifiesApp)
      ) { isOn in
        Label(isOn ? onLabel : offLabel, systemImage: isOn ? systemImageOn : systemImageOff)
      }
    }
    .displayName(LocalizedStringResource(stringLiteral: title))
    .description(LocalizedStringResource(stringLiteral: galleryDescription))
  }
}

// MARK: - Button

/// Opens the Flutter app with an action payload.
///
/// Queues a `button` action in the App Group (so it is delivered even if the deep link is
/// lost) and returns an `OpenURLIntent` for
/// `<urlScheme>://flutter-control-center/action?...`, which launches or foregrounds the app.
@available(iOS 18.0, *)
public struct FlutterOpenAppIntent: AppIntent {
  public static let title: LocalizedStringResource = "Open Flutter app from control"
  public static let isDiscoverable = false

  @Parameter(title: "Control kind")
  public var kind: String

  @Parameter(title: "Action")
  public var action: String

  @Parameter(title: "Payload (JSON)", default: "{}")
  public var payloadJSON: String

  public init() {}

  public init(kind: String, action: String, payload: [String: String]) {
    self.kind = kind
    self.action = action
    self.payloadJSON = FlutterControlsShared.encode(payload: payload)
  }

  public func perform() async throws -> some IntentResult & OpensIntent {
    let store = try FlutterControlsShared.store()
    let entry = FlutterControlCenterStore.makeAction(
      kind: kind, type: FlutterControlCenterStore.typeButton, action: action, value: nil,
      payload: FlutterControlsShared.decode(payload: payloadJSON))
    store.enqueue(action: entry)
    store.postChangeNotification()
    let scheme = FlutterControlCenterConfiguration.urlScheme
    guard let url = FlutterControlCenterStore.actionURL(scheme: scheme, action: entry) else {
      throw FlutterControlsError.invalidURLScheme(scheme)
    }
    return .result(opensIntent: OpenURLIntent(url))
  }
}

/// A button control that opens the Flutter app and delivers an action to
/// `FlutterControlCenter.actions`.
///
/// ```swift
/// struct StartTimerControl: FlutterControlButton {
///   static let kind = "start_timer"
///   let title = "Start timer"
///   let systemImage = "timer"
///   var payload: [String: String] { ["minutes": "25"] }
/// }
/// ```
@available(iOS 18.0, *)
public protocol FlutterControlButton: ControlWidget {
  /// Unique control kind; the same string is used from Dart.
  static var kind: String { get }
  /// Title shown on the control.
  var title: String { get }
  /// SF Symbol shown on the control. Defaults to `"app.badge"`.
  var systemImage: String { get }
  /// Action name delivered to Dart. Defaults to ``kind``.
  var action: String { get }
  /// String payload delivered to Dart. Defaults to empty.
  var payload: [String: String] { get }
  /// Description shown in the controls gallery. Defaults to ``title``.
  var galleryDescription: String { get }
}

@available(iOS 18.0, *)
extension FlutterControlButton {
  public var systemImage: String { "app.badge" }
  public var action: String { Self.kind }
  public var payload: [String: String] { [:] }
  public var galleryDescription: String { title }

  public var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(
        action: FlutterOpenAppIntent(kind: Self.kind, action: action, payload: payload)
      ) {
        Label(title, systemImage: systemImage)
      }
    }
    .displayName(LocalizedStringResource(stringLiteral: title))
    .description(LocalizedStringResource(stringLiteral: galleryDescription))
  }
}

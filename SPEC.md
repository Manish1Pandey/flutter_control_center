# flutter_control_center — Specification

## Purpose

iOS 18 added **controls**: small buttons and toggles that users place in Control Center,
on the Lock Screen and on the Action button. They are built with WidgetKit's `ControlWidget`
(`ControlWidgetButton` / `ControlWidgetToggle`) and backed by App Intents, and they live in a
**Widget Extension** target. No Flutter package supports them (`home_widget` covers Home
Screen widgets only).

This package makes controls usable from a Flutter app:

1. A **Dart API** that owns the controls' state (stored in a shared App Group), asks the system
   to re-render controls, and delivers control actions (button presses, toggle flips) to Dart.
2. A **Swift kit** copied into the Widget Extension that provides generic, configurable
   building blocks (`FlutterControlToggle`, `FlutterControlButton`, `FlutterSetValueIntent`,
   `FlutterOpenAppIntent`) that read/write the same App Group state.
3. A **setup CLI** (`dart run flutter_control_center:setup`) that writes the extension's Swift
   files and prints the exact Xcode steps that cannot be automated safely.

## Functional requirements

| ID | Requirement |
|----|-------------|
| FR1 | `configure(appGroup:)` selects the App Group (`UserDefaults(suiteName:)`) used for state; it is persisted natively so actions that launch the app are drained before Dart runs again. Fails with a clear error if the app is not entitled to the group (device). |
| FR2 | `setToggleState(kind, isOn)` writes a toggle's state to the App Group and (by default) reloads that control via `ControlCenter.shared.reloadControls(ofKind:)`. |
| FR3 | `getState(kind)` / `getAllStates()` return the stored state (value, last update time, whether the app or the control wrote it). `clearState(kind)` removes it. |
| FR4 | `reloadControls([kind])` reloads one kind or, with no kind, all controls; `reloadAll()` calls `ControlCenter.shared.reloadAllControls()`. |
| FR5 | `getInstalledControls()` returns the kinds the user has currently placed (`ControlCenter.shared.currentControls()`). |
| FR6 | `actions` is a stream of `ControlAction`s: a button that opens the app (`FlutterOpenAppIntent` → `OpenURLIntent` deep link) or a toggle flipped from Control Center (`FlutterSetValueIntent` with `notifyApp`). Delivery paths: deep link (`application:openURL:` / `scene:openURLContexts:` incl. cold launch), a Darwin notification while the app runs, and a queue in the App Group drained whenever the app becomes active. Actions carry a UUID and are delivered at most once; actions arriving before Dart listens are buffered. |
| FR7 | Swift kit: `FlutterControlToggle` (protocol with default `body`) renders a `ControlWidgetToggle` whose value comes from the App Group; `FlutterSetValueIntent` stores the new value, optionally queues an action and posts a Darwin notification. `FlutterControlButton` renders a `ControlWidgetButton` running `FlutterOpenAppIntent`, which queues an action with a string payload and opens the app via its URL scheme. |
| FR8 | Setup CLI: validates the App Group / URL scheme / kinds, writes `FlutterControlCenterStore.swift`, `FlutterControls.swift`, `FlutterControlCenterConfiguration.swift` and `<Extension>Bundle.swift` (one control per `--toggle` / `--button`), never overwrites user-edited files without `--force`, flags leftover Xcode template files, and prints the Xcode steps. |
| FR9 | On Android, web, desktop and iOS < 18, `isSupported()` returns `false`, `actions` is empty and every other call throws `ControlCenterUnsupportedException` (no crashes, no `MissingPluginException`). |

## Can / Cannot

| Can | Cannot (platform limits, stated honestly) |
|-----|-------------------------------------------|
| Store toggle state in an App Group that the extension reads | Draw control UI from Dart — controls are rendered by the system from Swift in the extension process |
| Reload one / all controls from Dart | Create the Widget Extension target or App Group entitlement automatically — `project.pbxproj` and provisioning edits are done in Xcode (steps printed + in README) |
| Deliver button presses to Dart with a string payload, cold or warm launch | Run Dart code when a toggle is flipped while the app is not running — the intent runs in the extension; the app sees the change (queued) next time it becomes active |
| Notify a running app of toggle flips (Darwin notification) | Receive Darwin notifications while the app is suspended (iOS does not deliver them) |
| List the controls the user has installed | Work on iOS < 18, Android, web or desktop — reported as unsupported |
| Ship the Swift kit as source copied into the extension | Ship the kit as a CocoaPod/SPM product: App Intents metadata is extracted per target, so intents must be compiled into the extension target itself |

## Public API sketch (Dart)

```dart
abstract final class FlutterControlCenter {
  static Future<bool> isSupported();
  static Future<void> configure({required String appGroup});
  static Future<void> setToggleState(String kind, bool isOn, {bool reload = true});
  static Future<ControlState?> getState(String kind);
  static Future<Map<String, ControlState>> getAllStates();
  static Future<void> clearState(String kind, {bool reload = true});
  static Future<void> reloadControls([String? kind]);
  static Future<void> reloadAll();
  static Future<List<String>> getInstalledControls();
  static Stream<ControlAction> get actions;
}
class ControlState { String kind; bool isOn; DateTime updatedAt; ControlStateSource source; }
class ControlAction { String id; String kind; ControlActionType type; String? action;
                      bool? value; Map<String, String> payload; DateTime timestamp; }
```

Swift kit (in the extension):

```swift
struct FocusModeControl: FlutterControlToggle {
  static let kind = "focus_mode"
  let title = "Focus mode"
  let systemImageOn = "moon.fill"
}
struct StartTimerControl: FlutterControlButton {
  static let kind = "start_timer"
  let title = "Start timer"
  let systemImage = "timer"
  var payload: [String: String] { ["minutes": "25"] }
}
```

## Platform matrix

| Platform | Status |
|----------|--------|
| iOS 18+ | Supported (plugin + Widget Extension kit) |
| iOS 13–17 | Builds; `isSupported()` = false, calls throw `ControlCenterUnsupportedException` |
| Android, web, macOS, Windows, Linux | No native code; `isSupported()` = false, calls throw `ControlCenterUnsupportedException` |

## Storage protocol (shared by app and extension, `FlutterControlCenterStore.swift`)

* State: key `fcc.v1.state.<kind>` → `{isOn: Bool, updatedAt: Double(ms), source: "app"|"control"}`
* Action queue: key `fcc.v1.actions` → `[{id, kind, type: "button"|"toggle", action?, value?, payload{String:String}, timestamp}]`, capped at 100
* Darwin notification: `<appGroup>.fcc.v1.changed`
* Deep link: `<scheme>://flutter-control-center/action?id=…&kind=…&type=…&action=…&timestamp=…&p.<key>=<value>`

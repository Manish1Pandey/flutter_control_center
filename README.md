# flutter_control_center

Add iOS 18 **controls** to your Flutter app. Controls are the small buttons and toggles users
place in **Control Center**, on the **Lock Screen** and on the **Action button**.

iOS 18 builds controls with WidgetKit's `ControlWidget` (`ControlWidgetButton`,
`ControlWidgetToggle`) and backs them with App Intents. Before this package, Flutter had no way to
use them, because `home_widget` only covers Home Screen and Lock Screen widgets. Flutter apps
that want controls end up writing the native bridge by hand. An example is
[BasedHardware/omi#6929](https://github.com/BasedHardware/omi/issues/6929), *"Control Center
widget for mute/unmute toggle (iOS 18+)"*, a Flutter app. As of September 2026, neither
`flutter/flutter` nor `ABausG/home_widget` has an issue tracking this. Report problems with this
package at
[its issue tracker](https://github.com/Manish1Pandey/flutter_control_center/issues).

This package gives you:

| Part | What it does |
|------|--------------|
| **Dart API** (`FlutterControlCenter`) | Stores toggle state in a shared App Group, reloads controls, lists installed controls, and gives you a **stream of control actions** (button presses that open the app, toggle flips). |
| **Swift kit** (copied into your Widget Extension) | `FlutterControlToggle` / `FlutterControlButton` protocols. You declare a control in about four lines. It also includes `FlutterSetValueIntent` (stores the value and can signal the app with a Darwin notification) and `FlutterOpenAppIntent` (queues the action and opens the app through your URL scheme). |
| **Setup CLI** (`dart run flutter_control_center:setup`) | Writes the extension's Swift files and prints the Xcode steps for your project. |

> **Honest constraint:** controls run inside a **Widget Extension** written in Swift. Dart cannot
> draw a control. You create the extension target once in Xcode (about 5 minutes, steps below).
> After that, your app drives the controls from Dart.

## Platform support

| Platform | Support |
|----------|---------|
| iOS 18+ | ✅ Full support |
| iOS 13–17 | Builds. `isSupported()` returns `false` and calls throw `ControlCenterUnsupportedException`. |
| Android, web, macOS, Windows, Linux | `isSupported()` returns `false`, `actions` never emits and calls throw `ControlCenterUnsupportedException`. No crashes and no `MissingPluginException`. |

## Install

```sh
flutter pub add flutter_control_center
```

## Setup (once per app)

Choose three values:

- **App Group**, e.g. `group.com.example.myapp`
- **URL scheme**, e.g. `myapp`
- **control kinds**, e.g. `focus_mode` and `start_timer`

### 1. Create the Widget Extension in Xcode

1. `open ios/Runner.xcworkspace`
2. **File > New > Target… > iOS > Widget Extension > Next.**
   - Product Name: `ControlCenterExtension`.
   - Untick *Include Live Activity*, *Include Control* and *Include Configuration App Intent*.
   - Embed in Application: **Runner**.
   - Click Finish, then **Don't Activate** when Xcode asks about the scheme.
3. In `ios/ControlCenterExtension`, delete the Swift files Xcode generated. Keep
   `ControlCenterExtensionBundle.swift`, because the CLI replaces it with `--force`.
4. Select the **ControlCenterExtension** target > General > Minimum Deployments: **iOS 18.0**.
5. Open **Signing & Capabilities** on the **Runner** target, then click **+ Capability > App Groups**
   and add `group.com.example.myapp`. Repeat for **ControlCenterExtension** with the same group.
   Both targets need the same Team.
6. **Runner** target > Info > **URL Types** > **+**: set Identifier and URL Schemes to `myapp`.
7. **Runner** target > **Build Phases**: drag **Embed Foundation Extensions** above
   **Thin Binary**. If you skip this, Flutter builds fail with *"Cycle inside Runner"*.
8. Optional: in the **ControlCenterExtension** build settings, set `MARKETING_VERSION` to
   `$(FLUTTER_BUILD_NAME)` and `CURRENT_PROJECT_VERSION` to `$(FLUTTER_BUILD_NUMBER)`.

Xcode 16+ creates a *synchronized* folder, so files you add to `ios/ControlCenterExtension` are
compiled into the extension automatically.

### 2. Generate the Swift files

```sh
dart run flutter_control_center:setup --force \
  --app-group group.com.example.myapp \
  --url-scheme myapp \
  --toggle "focus_mode:Focus mode" \
  --button "start_timer:Start timer"
```

The CLI writes four files to `ios/ControlCenterExtension/`:

| File | Owner |
|------|-------|
| `FlutterControlCenterStore.swift` | Plugin. This is the storage protocol shared with the app. Always refreshed. |
| `FlutterControls.swift` | Plugin. This is the kit (protocols and intents). Always refreshed. |
| `FlutterControlCenterConfiguration.swift` | Generated from `--app-group` and `--url-scheme`. |
| `ControlCenterExtensionBundle.swift` | **Yours.** It holds one struct per control and the `@main` `WidgetBundle`. The CLI overwrites it only with `--force`. |

The CLI also warns about leftover Xcode template files that declare `@main` or a widget.
After you upgrade the plugin, run `dart run flutter_control_center:setup --update-kit`.

Other options: `--extension-name`, `--ios-dir`, `--help`.

### 3. Customize the controls (Swift, optional)

```swift
struct FocusModeControl: FlutterControlToggle {
  static let kind = "focus_mode"
  let title = "Focus mode"
  let systemImageOn = "moon.fill"
  let systemImageOff = "moon"
  // optional: onLabel, offLabel, defaultValue, notifiesApp, galleryDescription
}

struct StartTimerControl: FlutterControlButton {
  static let kind = "start_timer"
  let title = "Start timer"
  let systemImage = "timer"
  var payload: [String: String] { ["minutes": "25"] }   // delivered to Dart
  // optional: action (defaults to kind), galleryDescription
}
```

## Usage (Dart)

```dart
import 'package:flutter_control_center/flutter_control_center.dart';

Future<void> setUpControls() async {
  if (!await FlutterControlCenter.isSupported()) return; // Android, web, iOS < 18

  FlutterControlCenter.actions.listen((ControlAction action) {
    switch (action.type) {
      case ControlActionType.button: // app was opened by the control
        if (action.kind == 'start_timer') {
          startTimer(int.parse(action.payload['minutes'] ?? '25'));
        }
      case ControlActionType.toggle: // flipped in Control Center
        setFocusMode(action.value!);
    }
  });

  await FlutterControlCenter.configure(appGroup: 'group.com.example.myapp');

  // Drive the toggle from the app; the control re-renders immediately.
  await FlutterControlCenter.setToggleState('focus_mode', true);

  final ControlState? state = await FlutterControlCenter.getState('focus_mode');
  print('${state?.isOn} written by ${state?.source.name}');

  await FlutterControlCenter.reloadControls('focus_mode'); // one kind
  await FlutterControlCenter.reloadAll();                  // everything
  final List<String> placed = await FlutterControlCenter.getInstalledControls();
}
```

| API | Notes |
|-----|-------|
| `isSupported()` | `true` only on iOS 18+. |
| `configure(appGroup:)` | Required once. The value is remembered natively. You can also set it in `Info.plist` with the key `FlutterControlCenterAppGroup`, so actions that launch the app are picked up before Dart runs. Throws `FlutterControlCenterException('app_group_unavailable')` if the app is not entitled to the group. |
| `setToggleState(kind, isOn, {reload = true})` | Writes the App Group state and calls `ControlCenter.shared.reloadControls(ofKind:)`. |
| `getState(kind)` / `getAllStates()` | Returns `ControlState(kind, isOn, updatedAt, source: app\|control)`. |
| `clearState(kind, {reload = true})` | The control falls back to its Swift `defaultValue`. |
| `reloadControls([kind])` / `reloadAll()` | `reloadControls(ofKind:)` / `reloadAllControls()`. |
| `getInstalledControls()` | `ControlCenter.shared.currentControls()` kinds. |
| `actions` | Broadcast `Stream<ControlAction>` with fields `id`, `kind`, `type`, `action`, `value`, `payload` and `timestamp`. |

### How actions reach Dart

1. **Button:** `FlutterOpenAppIntent` queues the action in the App Group, posts a Darwin
   notification, and returns `OpenURLIntent(myapp://flutter-control-center/action?...)`.
   The plugin handles that URL, including on cold launch, for both UIScene and AppDelegate apps.
2. **Toggle:** `FlutterSetValueIntent` stores the value. If `notifiesApp` is `true` (the default),
   it also queues a `toggle` action and posts a Darwin notification. A running app gets the action
   immediately. A suspended or terminated app gets it the next time it becomes active.
3. The queue is drained every time the app becomes active. Every action has a UUID and is
   delivered once. Actions that arrive before you listen are buffered.

Other deep links pass through to your app's own handling untouched.

## Limitations

- **Xcode steps are manual.** Target creation, App Group entitlements, the URL scheme and
  build-phase order change `project.pbxproj` and signing. This package documents these steps but
  does not automate them.
- **The kit is copied source, not a CocoaPod or SPM product.** App Intents metadata is extracted
  per target, so the intents must compile inside the extension target.
- **No Dart runs in the extension.** A toggle flipped while the app is closed only updates the
  stored value. The app sees the change when it next becomes active. Darwin notifications are not
  delivered to suspended apps.
- State lives in `UserDefaults` of the App Group. Keep values small. Writes from the app and the
  extension happening at the same moment use last-writer-wins.
- On a device, the App Group must be in your provisioning profile. The simulator does not enforce
  App Group entitlements.
- Button payloads are string-to-string maps. Encode anything richer yourself, for example as JSON.

## Example

`example/` is a Flutter app with a real Widget Extension target (`ControlCenterExtension`). It
has a **Focus mode** toggle and a **Start timer** button. The button opens the app, which then
starts a countdown from the payload. The example also shows every Dart API.

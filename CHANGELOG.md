## 0.1.0

* Initial release.
* Dart API: `configure`, `isSupported`, `setToggleState`, `getState`, `getAllStates`,
  `clearState`, `reloadControls`, `reloadAll`, `getInstalledControls` and the `actions` stream.
* Native iOS plugin: App Group state, `ControlCenter` reloads, and action delivery through deep
  links (UIScene and AppDelegate), Darwin notifications and an App Group queue.
* Swift kit for the Widget Extension: `FlutterControlToggle`, `FlutterControlButton`,
  `FlutterSetValueIntent` and `FlutterOpenAppIntent`.
* `dart run flutter_control_center:setup` CLI that generates the extension files and prints the
  Xcode steps.
* Non-iOS platforms and iOS < 18 report unsupported cleanly.

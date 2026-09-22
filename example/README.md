# flutter_control_center example

A Flutter app with a real iOS **Widget Extension** (`ios/ControlCenterExtension`) providing two
iOS 18 controls:

* **Focus mode** (`focus_mode`) — a toggle. Flip it in the app or in Control Center; both sides
  share the value through the App Group `group.com.manishpanday.flutterControlCenterExample`.
* **Start timer** (`start_timer`) — a button. It opens the app through the `fccexample://` URL
  scheme and the app starts a countdown from the `minutes` payload.

The extension's Swift files were generated with:

```sh
dart run flutter_control_center:setup \
  --app-group group.com.manishpanday.flutterControlCenterExample \
  --url-scheme fccexample \
  --toggle "focus_mode:Focus mode" --button "start_timer:Start timer"
```

and `ControlCenterExtensionBundle.swift` was then edited (SF Symbols, timer payload).

Run on an iOS 18+ simulator or device (a device needs your Team and an App Group you own):

```sh
flutter run
```

Then open Control Center, tap **+ > Add a Control**, and search for "Flutter Control Center".

/// iOS 18+ controls (Control Center, Lock Screen, Action button) for Flutter.
///
/// Controls are WidgetKit `ControlWidget`s that live in a Widget Extension
/// written in Swift. This library is the Flutter app's side: it stores the
/// controls' state in a shared App Group, asks the system to reload controls,
/// and delivers control actions (button presses, toggle flips) as a stream.
///
/// ```dart
/// await FlutterControlCenter.configure(appGroup: 'group.com.example.app');
/// await FlutterControlCenter.setToggleState('focus_mode', true);
/// FlutterControlCenter.actions.listen((action) {
///   if (action.kind == 'start_timer') startTimer();
/// });
/// ```
///
/// The Swift side is generated with `dart run flutter_control_center:setup`;
/// see the README for the Xcode steps.
library;

export 'src/flutter_control_center.dart';
export 'src/exceptions.dart';
export 'src/models.dart';

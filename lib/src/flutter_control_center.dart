import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'exceptions.dart';
import 'models.dart';

/// Entry point for iOS 18+ controls (Control Center, Lock Screen, Action
/// button).
///
/// Call [configure] once at startup with the App Group shared with your Widget
/// Extension, then read and write control state, reload controls and listen
/// to [actions].
///
/// On every platform other than iOS 18+, [isSupported] returns `false`,
/// [actions] never emits and all other methods throw
/// [ControlCenterUnsupportedException].
abstract final class FlutterControlCenter {
  /// Method channel shared with the native plugin.
  @visibleForTesting
  static const MethodChannel methodChannel = MethodChannel(
    'flutter_control_center',
  );

  /// Event channel carrying control actions from the native plugin.
  @visibleForTesting
  static const EventChannel eventChannel = EventChannel(
    'flutter_control_center/actions',
  );

  static Stream<ControlAction>? _actions;

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String get _platformName =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Whether controls can be used here: `true` only on iOS 18 or later.
  static Future<bool> isSupported() async {
    if (!_isIOS) {
      return false;
    }
    return await methodChannel.invokeMethod<bool>('isSupported') ?? false;
  }

  /// Selects the App Group whose `UserDefaults` suite holds control state.
  ///
  /// [appGroup] must match `FlutterControlCenterConfiguration.appGroup` in the
  /// Widget Extension and be enabled for both targets in Xcode. The value is
  /// remembered natively, so actions that launch the app are picked up even
  /// before this is called again.
  ///
  /// Throws [FlutterControlCenterException] with code `app_group_unavailable`
  /// when the app is not entitled to the group.
  static Future<void> configure({required String appGroup}) async {
    if (!appGroup.startsWith('group.') || appGroup.length <= 'group.'.length) {
      throw ArgumentError.value(
        appGroup,
        'appGroup',
        "must be an App Group identifier such as 'group.com.example.app'",
      );
    }
    await _invoke<void>('configure', <String, Object?>{'appGroup': appGroup});
  }

  /// Stores [isOn] as the value of the toggle [kind] and, when [reload] is
  /// true, asks the system to re-render that control.
  static Future<void> setToggleState(
    String kind,
    bool isOn, {
    bool reload = true,
  }) {
    _checkKind(kind);
    return _invoke<void>('setToggleState', <String, Object?>{
      'kind': kind,
      'isOn': isOn,
      'reload': reload,
    });
  }

  /// Returns the stored state of [kind], or `null` if nothing was stored yet.
  static Future<ControlState?> getState(String kind) async {
    _checkKind(kind);
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'getState',
      <String, Object?>{'kind': kind},
    );
    return raw == null ? null : ControlState.fromMap(raw);
  }

  /// Returns every stored control state keyed by kind.
  static Future<Map<String, ControlState>> getAllStates() async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'getAllStates',
    );
    if (raw == null) {
      return const <String, ControlState>{};
    }
    return <String, ControlState>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        entry.key! as String: ControlState.fromMap(
          entry.value! as Map<Object?, Object?>,
        ),
    };
  }

  /// Removes the stored state of [kind]; the control falls back to its Swift
  /// `defaultValue`. Reloads the control when [reload] is true.
  static Future<void> clearState(String kind, {bool reload = true}) {
    _checkKind(kind);
    return _invoke<void>('clearState', <String, Object?>{
      'kind': kind,
      'reload': reload,
    });
  }

  /// Asks the system to re-render the controls of [kind]
  /// (`ControlCenter.shared.reloadControls(ofKind:)`), or all controls when
  /// [kind] is `null`.
  static Future<void> reloadControls([String? kind]) {
    if (kind == null) {
      return reloadAll();
    }
    _checkKind(kind);
    return _invoke<void>('reloadControls', <String, Object?>{'kind': kind});
  }

  /// Asks the system to re-render every control of this app
  /// (`ControlCenter.shared.reloadAllControls()`).
  static Future<void> reloadAll() => _invoke<void>('reloadAllControls');

  /// Returns the kinds of the controls the user has currently placed in
  /// Control Center, on the Lock Screen or on the Action button.
  static Future<List<String>> getInstalledControls() async {
    final List<Object?>? raw = await _invoke<List<Object?>>(
      'getInstalledControls',
    );
    return List<String>.unmodifiable(raw?.cast<String>() ?? const <String>[]);
  }

  /// Control actions: button presses that opened the app and toggle flips
  /// (when the toggle's `notifiesApp` is true).
  ///
  /// Actions that happened while the app was not running are delivered when
  /// the app next becomes active; each action is delivered once. The stream is
  /// broadcast. On unsupported platforms it never emits.
  static Stream<ControlAction> get actions {
    if (!_isIOS) {
      return const Stream<ControlAction>.empty();
    }
    return _actions ??= eventChannel
        .receiveBroadcastStream()
        .where((Object? event) => event is Map)
        .map(
          (Object? event) =>
              ControlAction.fromMap(event! as Map<Object?, Object?>),
        );
  }

  /// Forgets the cached [actions] stream so tests can install a new mock.
  @visibleForTesting
  static void resetForTesting() {
    _actions = null;
  }

  static void _checkKind(String kind) {
    if (kind.isEmpty) {
      throw ArgumentError.value(kind, 'kind', 'must not be empty');
    }
  }

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!_isIOS) {
      throw ControlCenterUnsupportedException(
        'Controls are only available on iOS 18+; this is $_platformName.',
      );
    }
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      final String message = error.message ?? error.code;
      if (error.code == 'unsupported') {
        throw ControlCenterUnsupportedException(message);
      }
      throw FlutterControlCenterException(error.code, message);
    }
  }
}

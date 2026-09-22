import 'package:flutter/foundation.dart';

/// Who last wrote a control's state.
enum ControlStateSource {
  /// The Flutter app, through `FlutterControlCenter.setToggleState`.
  app,

  /// The control itself, when the user flipped it in Control Center, on the
  /// Lock Screen or with the Action button.
  control;

  static ControlStateSource _parse(Object? raw) =>
      raw == 'control' ? ControlStateSource.control : ControlStateSource.app;
}

/// Stored state of a toggle control, read from the shared App Group.
@immutable
class ControlState {
  /// Creates a state value.
  const ControlState({
    required this.kind,
    required this.isOn,
    required this.updatedAt,
    required this.source,
  });

  /// Decodes the map sent by the native side.
  factory ControlState.fromMap(Map<Object?, Object?> map) {
    return ControlState(
      kind: map['kind']! as String,
      isOn: map['isOn']! as bool,
      updatedAt: _millisToDate(map['updatedAt']),
      source: ControlStateSource._parse(map['source']),
    );
  }

  /// The control kind, identical to `static let kind` in Swift.
  final String kind;

  /// Whether the toggle is on.
  final bool isOn;

  /// When the value was last written.
  final DateTime updatedAt;

  /// Who wrote the value last.
  final ControlStateSource source;

  @override
  bool operator ==(Object other) =>
      other is ControlState &&
      other.kind == kind &&
      other.isOn == isOn &&
      other.updatedAt == updatedAt &&
      other.source == source;

  @override
  int get hashCode => Object.hash(kind, isOn, updatedAt, source);

  @override
  String toString() =>
      'ControlState($kind, isOn: $isOn, source: ${source.name}, '
      'updatedAt: ${updatedAt.toIso8601String()})';
}

/// What kind of control produced a [ControlAction].
enum ControlActionType {
  /// A `FlutterControlButton` was pressed; the app was opened.
  button,

  /// A `FlutterControlToggle` was flipped; [ControlAction.value] holds the
  /// new value.
  toggle;

  static ControlActionType _parse(Object? raw) =>
      raw == 'toggle' ? ControlActionType.toggle : ControlActionType.button;
}

/// An interaction with a control, delivered on `FlutterControlCenter.actions`.
@immutable
class ControlAction {
  /// Creates an action value.
  const ControlAction({
    required this.id,
    required this.kind,
    required this.type,
    required this.timestamp,
    this.action,
    this.value,
    this.payload = const <String, String>{},
  });

  /// Decodes the map sent by the native side.
  factory ControlAction.fromMap(Map<Object?, Object?> map) {
    final Object? rawPayload = map['payload'];
    return ControlAction(
      id: map['id']! as String,
      kind: map['kind']! as String,
      type: ControlActionType._parse(map['type']),
      action: map['action'] as String?,
      value: map['value'] as bool?,
      payload: rawPayload is Map
          ? Map<String, String>.unmodifiable(
              rawPayload.map(
                (Object? k, Object? v) => MapEntry(k.toString(), v.toString()),
              ),
            )
          : const <String, String>{},
      timestamp: _millisToDate(map['timestamp']),
    );
  }

  /// Unique id; each action is delivered at most once.
  final String id;

  /// The control kind, identical to `static let kind` in Swift.
  final String kind;

  /// Whether a button or a toggle produced the action.
  final ControlActionType type;

  /// For buttons: the `action` string configured in Swift (defaults to the
  /// kind). `null` for toggles.
  final String? action;

  /// For toggles: the new value. `null` for buttons.
  final bool? value;

  /// For buttons: the string payload configured in Swift.
  final Map<String, String> payload;

  /// When the control ran its intent.
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      other is ControlAction &&
      other.id == id &&
      other.kind == kind &&
      other.type == type &&
      other.action == action &&
      other.value == value &&
      mapEquals(other.payload, payload) &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    type,
    action,
    value,
    Object.hashAllUnordered(
      payload.entries.map(
        (MapEntry<String, String> e) => '${e.key}=${e.value}',
      ),
    ),
    timestamp,
  );

  @override
  String toString() =>
      'ControlAction($kind, type: ${type.name}, action: $action, '
      'value: $value, payload: $payload, id: $id)';
}

DateTime _millisToDate(Object? raw) {
  final num millis = raw is num ? raw : 0;
  return DateTime.fromMillisecondsSinceEpoch(millis.round());
}

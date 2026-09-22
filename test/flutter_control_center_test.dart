import 'dart:async';

import 'package:flutter_control_center/flutter_control_center.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final List<MethodCall> calls = <MethodCall>[];
  Object? Function(MethodCall call)? respond;

  setUp(() {
    calls.clear();
    respond = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterControlCenter.resetForTesting();
    messenger.setMockMethodCallHandler(FlutterControlCenter.methodChannel, (
      MethodCall call,
    ) async {
      calls.add(call);
      return respond?.call(call);
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(
      FlutterControlCenter.methodChannel,
      null,
    );
    messenger.setMockStreamHandler(FlutterControlCenter.eventChannel, null);
  });

  group('on iOS', () {
    test('isSupported forwards the native answer', () async {
      respond = (_) => true;
      expect(await FlutterControlCenter.isSupported(), isTrue);
      respond = (_) => false;
      expect(await FlutterControlCenter.isSupported(), isFalse);
      expect(calls.map((MethodCall c) => c.method), <String>[
        'isSupported',
        'isSupported',
      ]);
    });

    test('configure sends the App Group', () async {
      await FlutterControlCenter.configure(appGroup: 'group.com.example.app');
      expect(calls.single.method, 'configure');
      expect(calls.single.arguments, <String, Object?>{
        'appGroup': 'group.com.example.app',
      });
    });

    test('configure rejects identifiers that are not App Groups', () async {
      expect(
        () => FlutterControlCenter.configure(appGroup: 'com.example.app'),
        throwsArgumentError,
      );
      expect(
        () => FlutterControlCenter.configure(appGroup: 'group.'),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('setToggleState sends kind, value and reload flag', () async {
      await FlutterControlCenter.setToggleState('focus_mode', true);
      await FlutterControlCenter.setToggleState(
        'focus_mode',
        false,
        reload: false,
      );
      expect(calls[0].method, 'setToggleState');
      expect(calls[0].arguments, <String, Object?>{
        'kind': 'focus_mode',
        'isOn': true,
        'reload': true,
      });
      expect(calls[1].arguments, <String, Object?>{
        'kind': 'focus_mode',
        'isOn': false,
        'reload': false,
      });
    });

    test('empty kinds are rejected before reaching native code', () {
      expect(
        () => FlutterControlCenter.setToggleState('', true),
        throwsArgumentError,
      );
      expect(() => FlutterControlCenter.getState(''), throwsArgumentError);
      expect(() => FlutterControlCenter.clearState(''), throwsArgumentError);
      expect(
        () => FlutterControlCenter.reloadControls(''),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('getState decodes the native map', () async {
      respond = (_) => <String, Object?>{
        'kind': 'focus_mode',
        'isOn': true,
        'updatedAt': 1760000000000.0,
        'source': 'control',
      };
      final ControlState? state = await FlutterControlCenter.getState(
        'focus_mode',
      );
      expect(calls.single.arguments, <String, Object?>{'kind': 'focus_mode'});
      expect(
        state,
        ControlState(
          kind: 'focus_mode',
          isOn: true,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1760000000000),
          source: ControlStateSource.control,
        ),
      );
    });

    test('getState returns null when nothing is stored', () async {
      respond = (_) => null;
      expect(await FlutterControlCenter.getState('focus_mode'), isNull);
    });

    test('getAllStates decodes every entry', () async {
      respond = (_) => <String, Object?>{
        'a': <String, Object?>{
          'kind': 'a',
          'isOn': false,
          'updatedAt': 1000,
          'source': 'app',
        },
        'b': <String, Object?>{
          'kind': 'b',
          'isOn': true,
          'updatedAt': 2000,
          'source': 'control',
        },
      };
      final Map<String, ControlState> states =
          await FlutterControlCenter.getAllStates();
      expect(states.keys, unorderedEquals(<String>['a', 'b']));
      expect(states['a']!.isOn, isFalse);
      expect(states['a']!.source, ControlStateSource.app);
      expect(states['b']!.isOn, isTrue);
      expect(states['b']!.updatedAt.millisecondsSinceEpoch, 2000);
    });

    test('clearState sends kind and reload flag', () async {
      await FlutterControlCenter.clearState('focus_mode', reload: false);
      expect(calls.single.method, 'clearState');
      expect(calls.single.arguments, <String, Object?>{
        'kind': 'focus_mode',
        'reload': false,
      });
    });

    test('reloadControls reloads one kind, or all without a kind', () async {
      await FlutterControlCenter.reloadControls('focus_mode');
      await FlutterControlCenter.reloadControls();
      await FlutterControlCenter.reloadAll();
      expect(calls.map((MethodCall c) => c.method), <String>[
        'reloadControls',
        'reloadAllControls',
        'reloadAllControls',
      ]);
      expect(calls.first.arguments, <String, Object?>{'kind': 'focus_mode'});
    });

    test('getInstalledControls returns the kinds', () async {
      respond = (_) => <Object?>['focus_mode', 'start_timer'];
      expect(await FlutterControlCenter.getInstalledControls(), <String>[
        'focus_mode',
        'start_timer',
      ]);
    });

    test('native "unsupported" maps to ControlCenterUnsupportedException', () {
      respond = (_) => throw PlatformException(
        code: 'unsupported',
        message: 'Controls require iOS 18 or later (running 17.5).',
      );
      expect(
        () => FlutterControlCenter.reloadAll(),
        throwsA(
          isA<ControlCenterUnsupportedException>().having(
            (ControlCenterUnsupportedException e) => e.message,
            'message',
            contains('iOS 18'),
          ),
        ),
      );
    });

    test('other native errors map to FlutterControlCenterException', () {
      respond = (_) => throw PlatformException(
        code: 'not_configured',
        message: 'Call FlutterControlCenter.configure(appGroup: ...) first.',
      );
      expect(
        () => FlutterControlCenter.setToggleState('focus_mode', true),
        throwsA(
          isA<FlutterControlCenterException>().having(
            (FlutterControlCenterException e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
    });

    test('actions decodes events from the event channel', () async {
      messenger.setMockStreamHandler(
        FlutterControlCenter.eventChannel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events
              ..success(<String, Object?>{
                'id': 'A1',
                'kind': 'start_timer',
                'type': 'button',
                'action': 'start_timer',
                'payload': <String, Object?>{'minutes': '25'},
                'timestamp': 1760000000000.0,
              })
              ..success(<String, Object?>{
                'id': 'B2',
                'kind': 'focus_mode',
                'type': 'toggle',
                'value': true,
                'payload': <String, Object?>{},
                'timestamp': 1760000001000.0,
              })
              ..endOfStream();
          },
        ),
      );
      final List<ControlAction> received = await FlutterControlCenter.actions
          .toList();
      expect(received, hasLength(2));
      expect(
        received[0],
        ControlAction(
          id: 'A1',
          kind: 'start_timer',
          type: ControlActionType.button,
          action: 'start_timer',
          payload: const <String, String>{'minutes': '25'},
          timestamp: DateTime.fromMillisecondsSinceEpoch(1760000000000),
        ),
      );
      expect(received[1].type, ControlActionType.toggle);
      expect(received[1].value, isTrue);
      expect(received[1].action, isNull);
      expect(received[1].payload, isEmpty);
    });

    test('actions is a broadcast stream shared by listeners', () async {
      int listens = 0;
      messenger.setMockStreamHandler(
        FlutterControlCenter.eventChannel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            listens++;
            events.success(<String, Object?>{
              'id': 'C3',
              'kind': 'start_timer',
              'type': 'button',
              'action': 'go',
              'payload': <String, Object?>{},
              'timestamp': 1,
            });
          },
        ),
      );
      final Stream<ControlAction> stream = FlutterControlCenter.actions;
      expect(stream.isBroadcast, isTrue);
      expect(identical(stream, FlutterControlCenter.actions), isTrue);
      final Completer<ControlAction> first = Completer<ControlAction>();
      final Completer<ControlAction> second = Completer<ControlAction>();
      final StreamSubscription<ControlAction> a = stream.listen(first.complete);
      final StreamSubscription<ControlAction> b = stream.listen(
        second.complete,
      );
      expect((await first.future).id, 'C3');
      expect((await second.future).id, 'C3');
      expect(listens, 1);
      await a.cancel();
      await b.cancel();
    });
  });

  group('on other platforms', () {
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      test('${platform.name} reports unsupported cleanly', () async {
        debugDefaultTargetPlatformOverride = platform;
        expect(await FlutterControlCenter.isSupported(), isFalse);
        final List<Future<Object?> Function()> operations =
            <Future<Object?> Function()>[
              () => FlutterControlCenter.configure(appGroup: 'group.a.b'),
              () => FlutterControlCenter.setToggleState('k', true),
              () => FlutterControlCenter.getState('k'),
              () => FlutterControlCenter.getAllStates(),
              () => FlutterControlCenter.clearState('k'),
              () => FlutterControlCenter.reloadControls('k'),
              () => FlutterControlCenter.reloadAll(),
              () => FlutterControlCenter.getInstalledControls(),
            ];
        for (final Future<Object?> Function() operation in operations) {
          await expectLater(
            operation(),
            throwsA(
              isA<ControlCenterUnsupportedException>().having(
                (ControlCenterUnsupportedException e) => e.message,
                'message',
                contains(platform.name),
              ),
            ),
          );
        }
        expect(await FlutterControlCenter.actions.isEmpty, isTrue);
        expect(calls, isEmpty, reason: 'no channel traffic off iOS');
      });
    }
  });
}

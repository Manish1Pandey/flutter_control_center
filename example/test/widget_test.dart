import 'package:flutter_control_center/flutter_control_center.dart';
import 'package:flutter_control_center_example/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Map<String, Object?> stored;
  late List<MethodCall> calls;
  MockStreamHandlerEventSink? sink;

  setUp(() {
    stored = <String, Object?>{};
    calls = <MethodCall>[];
    sink = null;
    FlutterControlCenter.resetForTesting();
    messenger.setMockMethodCallHandler(FlutterControlCenter.methodChannel, (
      MethodCall call,
    ) async {
      calls.add(call);
      final Map<Object?, Object?> args =
          (call.arguments as Map<Object?, Object?>?) ?? <Object?, Object?>{};
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'setToggleState':
          stored[args['kind']! as String] = <String, Object?>{
            'kind': args['kind'],
            'isOn': args['isOn'],
            'updatedAt': 1760000000000,
            'source': 'app',
          };
          return null;
        case 'getState':
          return stored[args['kind']];
        case 'getAllStates':
          return stored;
        case 'clearState':
          stored.remove(args['kind']);
          return null;
        case 'getInstalledControls':
          return <String>['focus_mode', 'start_timer'];
        default:
          return null;
      }
    });
    messenger.setMockStreamHandler(
      FlutterControlCenter.eventChannel,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink events) {
          sink = events;
        },
      ),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(
      FlutterControlCenter.methodChannel,
      null,
    );
    messenger.setMockStreamHandler(FlutterControlCenter.eventChannel, null);
  });

  testWidgets('configures, toggles focus mode and clears it', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(const ControlsExampleApp());
    await tester.pumpAndSettle();

    expect(
      calls.where((MethodCall c) => c.method == 'configure').single.arguments,
      <String, Object?>{'appGroup': appGroup},
    );
    expect(find.textContaining('Not set yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('focus-switch')));
    await tester.pumpAndSettle();
    expect(
      calls
          .where((MethodCall c) => c.method == 'setToggleState')
          .single
          .arguments,
      <String, Object?>{'kind': focusModeKind, 'isOn': true, 'reload': true},
    );
    expect(find.textContaining('Last changed by the app'), findsOneWidget);
    expect(find.text('written by app'), findsOneWidget);

    await tester.tap(find.text('Clear state'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not set yet'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a Start timer action starts the countdown', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(const ControlsExampleApp());
    await tester.pumpAndSettle();

    expect(sink, isNotNull, reason: 'the app listens to actions');
    await tester.runAsync(() async {
      sink!.success(<String, Object?>{
        'id': 'X',
        'kind': startTimerKind,
        'type': 'button',
        'action': startTimerKind,
        'payload': <String, Object?>{'minutes': '2'},
        'timestamp': 1760000000000,
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.textContaining(RegExp(r'^0[12]:[0-5][0-9]$')), findsOneWidget);
    expect(find.textContaining('start_timer pressed'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(find.text('Start timer'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('focus_mode, start_timer'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows the unsupported notice off iOS', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const ControlsExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('Controls need iOS 18 or later.'), findsOneWidget);
    expect(calls, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });
}

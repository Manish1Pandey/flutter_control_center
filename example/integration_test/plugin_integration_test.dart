// Runs against the real native plugin on an iOS 18+ simulator or device:
//   flutter test integration_test -d <iOS 18 simulator>
// Set FCC_WAIT_FOR_DEEP_LINK=1 (via --dart-define) and open
//   fccexample://flutter-control-center/action?id=it-1&kind=start_timer&type=button&action=start_timer&p.minutes=25
// with `xcrun simctl openurl booted '<url>'` to also verify deep-link delivery.
import 'package:flutter_control_center/flutter_control_center.dart';
import 'package:flutter_control_center_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const bool waitForDeepLink = bool.fromEnvironment('FCC_WAIT_FOR_DEEP_LINK');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native plugin stores state and reloads controls', (_) async {
    expect(await FlutterControlCenter.isSupported(), isTrue);

    await FlutterControlCenter.configure(appGroup: appGroup);

    await FlutterControlCenter.setToggleState(focusModeKind, true);
    final ControlState? on = await FlutterControlCenter.getState(focusModeKind);
    expect(on?.isOn, isTrue);
    expect(on?.source, ControlStateSource.app);
    expect(
      on!.updatedAt.difference(DateTime.now()).inMinutes.abs(),
      lessThan(2),
    );

    await FlutterControlCenter.setToggleState(
      focusModeKind,
      false,
      reload: false,
    );
    expect((await FlutterControlCenter.getState(focusModeKind))?.isOn, isFalse);

    final Map<String, ControlState> all =
        await FlutterControlCenter.getAllStates();
    expect(all.keys, contains(focusModeKind));

    await FlutterControlCenter.clearState(focusModeKind);
    expect(await FlutterControlCenter.getState(focusModeKind), isNull);

    await FlutterControlCenter.reloadControls(focusModeKind);
    await FlutterControlCenter.reloadAll();

    final List<String> installed =
        await FlutterControlCenter.getInstalledControls();
    expect(installed, isA<List<String>>());
  });

  testWidgets('deep link from a control reaches the actions stream', (_) async {
    await FlutterControlCenter.configure(appGroup: appGroup);
    // ignore: avoid_print
    print('FCC_READY_FOR_DEEP_LINK');
    final ControlAction action = await FlutterControlCenter.actions
        .firstWhere((ControlAction a) => a.id == 'it-1')
        .timeout(const Duration(seconds: 90));
    expect(action.kind, startTimerKind);
    expect(action.type, ControlActionType.button);
    expect(action.payload, <String, String>{'minutes': '25'});
    // ignore: avoid_print
    print('FCC_DEEP_LINK_RECEIVED ${action.kind} ${action.payload}');
  }, skip: !waitForDeepLink);
}

import 'dart:io';

import 'package:flutter_control_center/src/setup/setup_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late Directory ios;
  final KitSources sources = KitSources(Directory.current.path);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fcc_setup_');
    ios = Directory('${temp.path}/ios')..createSync();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  SetupOptions options({
    List<ControlSpec>? controls,
    bool force = false,
    String appGroup = 'group.com.example.app',
    String urlScheme = 'myapp',
    String extensionName = 'ControlCenterExtension',
    bool updateKitOnly = false,
  }) => SetupOptions(
    iosDirectory: ios.path,
    extensionName: extensionName,
    appGroup: appGroup,
    urlScheme: urlScheme,
    controls:
        controls ??
        <ControlSpec>[
          ControlSpec.parse('focus_mode:Focus mode', ControlSpecType.toggle),
          ControlSpec.parse('start_timer', ControlSpecType.button),
        ],
    force: force,
    updateKitOnly: updateKitOnly,
  );

  String read(String name) =>
      File('${ios.path}/ControlCenterExtension/$name').readAsStringSync();

  group('ControlSpec.parse', () {
    test('splits kind and title and derives the struct name', () {
      final ControlSpec spec = ControlSpec.parse(
        'focus_mode:Focus mode',
        ControlSpecType.toggle,
      );
      expect(spec.kind, 'focus_mode');
      expect(spec.title, 'Focus mode');
      expect(spec.structName, 'FocusModeControl');
    });

    test('derives a title from the kind when none is given', () {
      final ControlSpec spec = ControlSpec.parse(
        'start-timer.now',
        ControlSpecType.button,
      );
      expect(spec.title, 'Start timer now');
      expect(spec.structName, 'StartTimerNowControl');
    });

    test('rejects kinds Swift and Dart cannot share', () {
      for (final String bad in <String>['', '1abc', 'has space', 'x/y:T']) {
        expect(
          () => ControlSpec.parse(bad, ControlSpecType.toggle),
          throwsA(isA<SetupException>()),
          reason: bad,
        );
      }
    });
  });

  group('validation', () {
    test('requires a proper App Group, URL scheme and controls', () {
      expect(
        () => runSetup(options(appGroup: 'com.example'), sources),
        throwsA(isA<SetupException>()),
      );
      expect(
        () => runSetup(options(urlScheme: '1bad'), sources),
        throwsA(isA<SetupException>()),
      );
      expect(
        () => runSetup(options(controls: <ControlSpec>[]), sources),
        throwsA(isA<SetupException>()),
      );
      expect(
        () => runSetup(options(extensionName: 'My Ext'), sources),
        throwsA(isA<SetupException>()),
      );
    });

    test('rejects duplicate kinds and more than 10 controls', () {
      final ControlSpec a = ControlSpec.parse('a', ControlSpecType.toggle);
      expect(
        () => runSetup(options(controls: <ControlSpec>[a, a]), sources),
        throwsA(isA<SetupException>()),
      );
      expect(
        () => runSetup(
          options(
            controls: List<ControlSpec>.generate(
              11,
              (int i) => ControlSpec.parse('k$i', ControlSpecType.button),
            ),
          ),
          sources,
        ),
        throwsA(isA<SetupException>()),
      );
    });

    test('fails when the ios directory is missing', () {
      ios.deleteSync();
      expect(
        () => runSetup(options(), sources),
        throwsA(isA<SetupException>()),
      );
    });
  });

  group('generation', () {
    test('writes the kit, store, configuration and bundle', () {
      final SetupResult result = runSetup(options(), sources);
      expect(result.written, hasLength(4));
      expect(result.skipped, isEmpty);
      expect(result.conflictingFiles, isEmpty);

      expect(read(storeFileName), File(sources.storePath).readAsStringSync());
      expect(read(kitFileName), File(sources.kitPath).readAsStringSync());

      final String config = read(configurationFileName);
      expect(config, contains('static let appGroup = "group.com.example.app"'));
      expect(config, contains('static let urlScheme = "myapp"'));

      final String bundle = read('ControlCenterExtensionBundle.swift');
      expect(bundle, contains('struct FocusModeControl: FlutterControlToggle'));
      expect(bundle, contains('static let kind = "focus_mode"'));
      expect(bundle, contains('let title = "Focus mode"'));
      expect(
        bundle,
        contains('struct StartTimerControl: FlutterControlButton'),
      );
      expect(bundle, contains('let title = "Start timer"'));
      expect(bundle, contains('@main'));
      expect(
        bundle,
        contains('struct ControlCenterExtensionBundle: WidgetBundle'),
      );
      expect(
        bundle,
        contains('    FocusModeControl()\n    StartTimerControl()'),
      );
    });

    test('escapes quotes and backslashes in titles', () {
      runSetup(
        options(
          controls: <ControlSpec>[
            ControlSpec.parse(r'q:Say "hi" \ bye', ControlSpecType.toggle),
          ],
        ),
        sources,
      );
      expect(
        read('ControlCenterExtensionBundle.swift'),
        contains(r'let title = "Say \"hi\" \\ bye"'),
      );
    });

    test('keeps an edited bundle unless --force, always refreshes the kit', () {
      runSetup(options(), sources);
      final File bundle = File(
        '${ios.path}/ControlCenterExtension/ControlCenterExtensionBundle.swift',
      );
      bundle.writeAsStringSync('// my edits\n');
      File(
        '${ios.path}/ControlCenterExtension/$kitFileName',
      ).writeAsStringSync('stale');

      final SetupResult second = runSetup(options(), sources);
      expect(second.skipped, <String>[bundle.path]);
      expect(bundle.readAsStringSync(), '// my edits\n');
      expect(read(kitFileName), File(sources.kitPath).readAsStringSync());

      final SetupResult forced = runSetup(options(force: true), sources);
      expect(forced.skipped, isEmpty);
      expect(bundle.readAsStringSync(), contains('FocusModeControl'));
    });

    test('--update-kit only needs the extension name', () {
      final SetupResult result = runSetup(
        SetupOptions(
          iosDirectory: ios.path,
          extensionName: 'ControlCenterExtension',
          updateKitOnly: true,
        ),
        sources,
      );
      expect(
        result.written.map((String p) => p.split('/').last),
        unorderedEquals(<String>[storeFileName, kitFileName]),
      );
    });

    test('flags Xcode template files that would clash', () {
      final Directory ext = Directory('${ios.path}/ControlCenterExtension')
        ..createSync();
      File(
        '${ext.path}/ControlCenterExtension.swift',
      ).writeAsStringSync('struct ControlCenterExtension: Widget { }');
      File(
        '${ext.path}/ControlCenterExtensionControl.swift',
      ).writeAsStringSync('struct X: ControlWidget { }');
      File('${ext.path}/Helpers.swift').writeAsStringSync('let x = 1');
      final SetupResult result = runSetup(options(force: true), sources);
      expect(
        result.conflictingFiles.map((String p) => p.split('/').last),
        <String>[
          'ControlCenterExtension.swift',
          'ControlCenterExtensionControl.swift',
        ],
      );
    });

    test('xcodeSteps names the concrete target, group and scheme', () {
      final String steps = xcodeSteps(options());
      expect(steps, contains('Product Name: ControlCenterExtension'));
      expect(steps, contains('"group.com.example.app"'));
      expect(steps, contains('URL Schemes "myapp"'));
      expect(steps, contains('iOS 18.0'));
      expect(steps, contains('Embed Foundation Extensions'));
    });
  });

  group('example app', () {
    test('ships the same kit and store the plugin ships', () {
      const String ext = 'example/ios/ControlCenterExtension';
      expect(
        File('$ext/$storeFileName').readAsStringSync(),
        File(sources.storePath).readAsStringSync(),
      );
      expect(
        File('$ext/$kitFileName').readAsStringSync(),
        File(sources.kitPath).readAsStringSync(),
      );
    });
  });

  group('CLI', () {
    test('writes files and prints the Xcode steps', () async {
      final ProcessResult result = await Process.run('dart', <String>[
        'run',
        'bin/setup.dart',
        '--ios-dir',
        ios.path,
        '--app-group',
        'group.com.example.app',
        '--url-scheme',
        'myapp',
        '--toggle',
        'focus_mode:Focus mode',
        '--button',
        'start_timer:Start timer',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('wrote'));
      expect(result.stdout, contains('Xcode steps'));
      expect(
        read('ControlCenterExtensionBundle.swift'),
        contains('Focus mode'),
      );
    });

    test('exits with 64 and a message on invalid input', () async {
      final ProcessResult result = await Process.run('dart', <String>[
        'run',
        'bin/setup.dart',
        '--ios-dir',
        ios.path,
        '--app-group',
        'nope',
        '--url-scheme',
        'myapp',
        '--toggle',
        'a',
      ]);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('--app-group'));
    });
  });
}

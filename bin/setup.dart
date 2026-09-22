import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:flutter_control_center/src/setup/setup_generator.dart';

/// `dart run flutter_control_center:setup` — writes the Widget Extension
/// Swift files for iOS controls and prints the Xcode steps.
Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'app-group',
      help:
          'App Group shared by the app and the extension '
          '(e.g. group.com.example.app).',
    )
    ..addOption(
      'url-scheme',
      help: 'URL scheme registered by the app; buttons open the app with it.',
    )
    ..addMultiOption(
      'toggle',
      help: 'Generate a toggle control: kind or kind:Title. Repeatable.',
      splitCommas: false,
    )
    ..addMultiOption(
      'button',
      help:
          'Generate a button control that opens the app: kind or '
          'kind:Title. Repeatable.',
      splitCommas: false,
    )
    ..addOption(
      'extension-name',
      defaultsTo: 'ControlCenterExtension',
      help: 'Widget Extension target name (folder under ios/).',
    )
    ..addOption(
      'ios-dir',
      defaultsTo: 'ios',
      help: "Path to the Flutter app's ios/ directory.",
    )
    ..addFlag(
      'force',
      negatable: false,
      help: 'Overwrite the existing <Extension>Bundle.swift.',
    )
    ..addFlag(
      'update-kit',
      negatable: false,
      help:
          'Only refresh FlutterControls.swift and '
          'FlutterControlCenterStore.swift (after upgrading the plugin).',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(parser.usage);
    exitCode = 64;
    return;
  }
  if (args.flag('help')) {
    stdout
      ..writeln('Usage: dart run flutter_control_center:setup [options]')
      ..writeln()
      ..writeln('Example:')
      ..writeln(
        '  dart run flutter_control_center:setup '
        '--app-group group.com.example.app --url-scheme myapp '
        '--toggle "focus_mode:Focus mode" --button "start_timer:Start timer"',
      )
      ..writeln()
      ..writeln(parser.usage);
    return;
  }

  final List<ControlSpec> controls;
  try {
    controls = <ControlSpec>[
      for (final String raw in args.multiOption('toggle'))
        ControlSpec.parse(raw, ControlSpecType.toggle),
      for (final String raw in args.multiOption('button'))
        ControlSpec.parse(raw, ControlSpecType.button),
    ];
  } on SetupException catch (error) {
    stderr.writeln('error: $error');
    exitCode = 64;
    return;
  }

  final SetupOptions options = SetupOptions(
    iosDirectory: args.option('ios-dir')!,
    extensionName: args.option('extension-name')!,
    appGroup: args.option('app-group'),
    urlScheme: args.option('url-scheme'),
    controls: controls,
    force: args.flag('force'),
    updateKitOnly: args.flag('update-kit'),
  );

  final Uri? libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_control_center/flutter_control_center.dart'),
  );
  if (libraryUri == null) {
    stderr.writeln(
      'error: cannot locate the flutter_control_center package; run '
      '`flutter pub get` first.',
    );
    exitCode = 69;
    return;
  }
  final String packageRoot = File.fromUri(libraryUri).parent.parent.path;

  final SetupResult result;
  try {
    result = runSetup(options, KitSources(packageRoot));
  } on SetupException catch (error) {
    stderr.writeln('error: $error');
    exitCode = 64;
    return;
  }

  for (final String path in result.written) {
    stdout.writeln('  wrote   $path');
  }
  for (final String path in result.skipped) {
    stdout.writeln('  kept    $path (exists; pass --force to replace)');
  }
  if (result.conflictingFiles.isNotEmpty) {
    stdout
      ..writeln()
      ..writeln(
        'warning: these files declare @main or a widget and will clash with '
        'the generated bundle; delete them (Xcode template files):',
      );
    for (final String path in result.conflictingFiles) {
      stdout.writeln('  $path');
    }
  }
  if (!options.updateKitOnly) {
    stdout
      ..writeln()
      ..write(xcodeSteps(options));
  }
}

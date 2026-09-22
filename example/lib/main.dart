import 'dart:async';

import 'package:flutter_control_center/flutter_control_center.dart';
import 'package:flutter/material.dart';

/// App Group enabled for Runner and ControlCenterExtension in Xcode.
const String appGroup = 'group.com.manishpanday.flutterControlCenterExample';

/// Kind of the "Focus mode" toggle (see ControlCenterExtensionBundle.swift).
const String focusModeKind = 'focus_mode';

/// Kind of the "Start timer" button (see ControlCenterExtensionBundle.swift).
const String startTimerKind = 'start_timer';

void main() {
  runApp(const ControlsExampleApp());
}

/// Example app for flutter_control_center.
class ControlsExampleApp extends StatelessWidget {
  /// Creates the app.
  const ControlsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Control Center',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const ControlsHomePage(),
    );
  }
}

/// Shows and drives the two controls of the example Widget Extension.
class ControlsHomePage extends StatefulWidget {
  /// Creates the page.
  const ControlsHomePage({super.key});

  @override
  State<ControlsHomePage> createState() => _ControlsHomePageState();
}

class _ControlsHomePageState extends State<ControlsHomePage>
    with WidgetsBindingObserver {
  bool? _supported;
  String? _error;
  ControlState? _focusState;
  Map<String, ControlState> _allStates = const <String, ControlState>{};
  List<String>? _installed;
  final List<ControlAction> _log = <ControlAction>[];
  StreamSubscription<ControlAction>? _subscription;

  Timer? _ticker;
  DateTime? _timerEnd;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _supported == true) {
      _refresh();
    }
  }

  Future<void> _start() async {
    final bool supported = await FlutterControlCenter.isSupported();
    if (!mounted) return;
    setState(() => _supported = supported);
    if (!supported) return;
    _subscription = FlutterControlCenter.actions.listen(_onAction);
    await _guard(() => FlutterControlCenter.configure(appGroup: appGroup));
    await _refresh();
  }

  Future<void> _refresh() async {
    await _guard(() async {
      final ControlState? focus = await FlutterControlCenter.getState(
        focusModeKind,
      );
      final Map<String, ControlState> all =
          await FlutterControlCenter.getAllStates();
      if (!mounted) return;
      setState(() {
        _focusState = focus;
        _allStates = all;
      });
    });
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
      if (mounted && _error != null) setState(() => _error = null);
    } on FlutterControlCenterException catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } on ControlCenterUnsupportedException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  void _onAction(ControlAction action) {
    setState(() => _log.insert(0, action));
    switch (action.type) {
      case ControlActionType.button when action.kind == startTimerKind:
        final int minutes = int.tryParse(action.payload['minutes'] ?? '') ?? 25;
        _startTimer(Duration(minutes: minutes));
      case ControlActionType.toggle:
        _refresh();
      case ControlActionType.button:
        break;
    }
  }

  void _startTimer(Duration duration) {
    _ticker?.cancel();
    _timerEnd = DateTime.now().add(duration);
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stopTimer() {
    _ticker?.cancel();
    setState(() {
      _timerEnd = null;
      _remaining = Duration.zero;
    });
  }

  void _tick() {
    final DateTime? end = _timerEnd;
    if (end == null) return;
    final Duration left = end.difference(DateTime.now());
    if (left <= Duration.zero) {
      _stopTimer();
      return;
    }
    setState(() => _remaining = left);
  }

  Future<void> _setFocus(bool isOn) async {
    await _guard(
      () => FlutterControlCenter.setToggleState(focusModeKind, isOn),
    );
    await _refresh();
  }

  Future<void> _clearFocus() async {
    await _guard(() => FlutterControlCenter.clearState(focusModeKind));
    await _refresh();
  }

  Future<void> _loadInstalled() async {
    await _guard(() async {
      final List<String> kinds =
          await FlutterControlCenter.getInstalledControls();
      if (mounted) setState(() => _installed = kinds);
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final bool? supported = _supported;
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Control Center')),
      body: switch (supported) {
        null => const Center(child: CircularProgressIndicator()),
        false => const _UnsupportedNotice(),
        true => _buildControls(context),
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ControlState? focus = _focusState;
    final bool timerRunning = _timerEnd != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (_error != null)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(_error!),
            ),
          ),
        Card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                key: const Key('focus-switch'),
                secondary: Icon(
                  focus?.isOn ?? false
                      ? Icons.dark_mode
                      : Icons.dark_mode_outlined,
                ),
                title: const Text('Focus mode'),
                subtitle: Text(
                  focus == null
                      ? 'Not set yet (control shows its Swift default)'
                      : 'Last changed by the ${focus.source.name} at '
                            '${TimeOfDay.fromDateTime(focus.updatedAt).format(context)}',
                ),
                value: focus?.isOn ?? false,
                onChanged: _setFocus,
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _clearFocus,
                    child: const Text('Clear state'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await _guard(
                        () =>
                            FlutterControlCenter.reloadControls(focusModeKind),
                      );
                      _snack('Reloaded $focusModeKind');
                    },
                    child: const Text('Reload control'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(
              timerRunning ? _format(_remaining) : 'Start timer',
              style: timerRunning ? theme.textTheme.headlineMedium : null,
            ),
            subtitle: Text(
              timerRunning
                  ? 'Started from the "Start timer" control'
                  : 'Press the "Start timer" control in Control Center, on '
                        'the Lock Screen or with the Action button.',
            ),
            trailing: timerRunning
                ? IconButton(
                    tooltip: 'Stop',
                    icon: const Icon(Icons.stop),
                    onPressed: _stopTimer,
                  )
                : null,
          ),
        ),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.widgets_outlined),
                title: const Text('Installed controls'),
                subtitle: Text(switch (_installed) {
                  null => 'Tap refresh to ask the system',
                  final List<String> kinds when kinds.isEmpty =>
                    'None placed yet: Control Center > + > Add a Control',
                  final List<String> kinds => kinds.join(', '),
                }),
                trailing: IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadInstalled,
                ),
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () async {
                      await _guard(FlutterControlCenter.reloadAll);
                      _snack('Reloaded all controls');
                    },
                    child: const Text('Reload all controls'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const ListTile(
                leading: Icon(Icons.storage_outlined),
                title: Text('App Group state'),
              ),
              if (_allStates.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text('Nothing stored'),
                )
              else
                for (final ControlState state in _allStates.values)
                  ListTile(
                    dense: true,
                    title: Text(state.kind),
                    trailing: Text(state.isOn ? 'on' : 'off'),
                    subtitle: Text('written by ${state.source.name}'),
                  ),
            ],
          ),
        ),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const ListTile(
                leading: Icon(Icons.history),
                title: Text('Control actions'),
              ),
              if (_log.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text('No actions received yet'),
                )
              else
                for (final ControlAction action in _log)
                  ListTile(
                    dense: true,
                    title: Text(
                      action.type == ControlActionType.toggle
                          ? '${action.kind} -> ${action.value! ? 'on' : 'off'}'
                          : '${action.kind} pressed (${action.action})',
                    ),
                    subtitle: Text(
                      '${action.timestamp.toLocal()}'
                      '${action.payload.isEmpty ? '' : '  ${action.payload}'}',
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  static String _format(Duration d) {
    final String minutes = d.inMinutes.toString().padLeft(2, '0');
    final String seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.phonelink_off, size: 48),
            SizedBox(height: 16),
            Text('Controls need iOS 18 or later.', textAlign: TextAlign.center),
            SizedBox(height: 8),
            Text(
              'On this platform FlutterControlCenter.isSupported() is false '
              'and every other call throws ControlCenterUnsupportedException.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

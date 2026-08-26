import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'application/jucier_shell.dart';
import 'archive/archive_engine.dart';
import 'archive/seven_zip_engine.dart';
import 'platform/file_access_service.dart';
import 'platform/theme_preference_store.dart';

export 'application/jucier_shell.dart' show JucierShell;

/// Configures global theming and wires the app's platform dependencies.
class JucierApp extends StatefulWidget {
  const JucierApp({
    super.key,
    this.engine,
    this.fileAccessService,
    this.themePreferenceStore,
  });

  final ArchiveEngine? engine;
  final FileAccessService? fileAccessService;
  final ThemePreferenceStore? themePreferenceStore;

  @override
  State<JucierApp> createState() => _JucierAppState();
}

class _JucierAppState extends State<JucierApp> {
  late final ArchiveEngine _engine;
  late final FileAccessService _fileAccessService;
  late final ThemePreferenceStore _themePreferenceStore;
  ThemeMode _themeMode = ThemeMode.system;
  bool _themeChangedByUser = false;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? SevenZipEngine();
    _fileAccessService = widget.fileAccessService ?? MacOSFileAccessService();
    _themePreferenceStore =
        widget.themePreferenceStore ?? MacOSThemePreferenceStore();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final mode = await _themePreferenceStore.load();
    if (mounted && !_themeChangedByUser) {
      setState(() => _themeMode = mode);
    }
  }

  void _setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeChangedByUser = true;
    setState(() => _themeMode = mode);
    _themePreferenceStore.save(mode);
  }

  @override
  Widget build(BuildContext context) {
    final light = FTheme.neutral.light.desktop;
    final dark = FTheme.neutral.dark.desktop;

    return MaterialApp(
      title: 'Jucier',
      debugShowCheckedModeBanner: false,
      theme: light.toApproximateMaterialTheme(),
      darkTheme: dark.toApproximateMaterialTheme(),
      themeMode: _themeMode,
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: const [...FLocalizations.localizationsDelegates],
      builder: (context, child) {
        final brightness = switch (_themeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
        };
        return FTheme(
          data: brightness == Brightness.dark ? dark : light,
          child: FToaster(
            child: FTooltipGroup(
              // Archive forms use a few Material controls. Forui scaffolds
              // and dialogs do not insert a Material ancestor themselves.
              child: Material(type: MaterialType.transparency, child: child!),
            ),
          ),
        );
      },
      home: JucierShell(
        engine: _engine,
        fileAccessService: _fileAccessService,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'application/jucier_shell.dart';
import 'archive/archive_column.dart';
import 'archive/archive_engine.dart';
import 'archive/seven_zip_engine.dart';
import 'platform/file_access_service.dart';
import 'platform/archive_column_preference_store.dart';
import 'platform/single_entry_extraction_preference_store.dart';
import 'platform/theme_preference_store.dart';

export 'application/jucier_shell.dart' show JucierShell;

/// Configures global theming and wires the app's platform dependencies.
class JucierApp extends StatefulWidget {
  const JucierApp({
    super.key,
    this.engine,
    this.fileAccessService,
    this.themePreferenceStore,
    this.singleEntryExtractionPreferenceStore,
    this.archiveColumnPreferenceStore,
  });

  final ArchiveEngine? engine;
  final FileAccessService? fileAccessService;
  final ThemePreferenceStore? themePreferenceStore;
  final SingleEntryExtractionPreferenceStore?
  singleEntryExtractionPreferenceStore;
  final ArchiveColumnPreferenceStore? archiveColumnPreferenceStore;

  @override
  State<JucierApp> createState() => _JucierAppState();
}

class _JucierAppState extends State<JucierApp> {
  late final ArchiveEngine _engine;
  late final FileAccessService _fileAccessService;
  late final ThemePreferenceStore _themePreferenceStore;
  late final SingleEntryExtractionPreferenceStore
  _singleEntryExtractionPreferenceStore;
  late final ArchiveColumnPreferenceStore _archiveColumnPreferenceStore;
  ThemeMode _themeMode = ThemeMode.system;
  SingleEntryExtractionMode _singleEntryExtractionMode =
      SingleEntryExtractionMode.preserveArchiveStructure;
  ArchiveColumnPreferences _archiveColumnPreferences =
      const ArchiveColumnPreferences();
  bool _themeChangedByUser = false;
  bool _singleEntryExtractionModeChangedByUser = false;
  bool _archiveColumnPreferencesChangedByUser = false;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? SevenZipEngine();
    _fileAccessService = widget.fileAccessService ?? MacOSFileAccessService();
    _themePreferenceStore =
        widget.themePreferenceStore ?? MacOSThemePreferenceStore();
    _singleEntryExtractionPreferenceStore =
        widget.singleEntryExtractionPreferenceStore ??
        MacOSSingleEntryExtractionPreferenceStore();
    _archiveColumnPreferenceStore =
        widget.archiveColumnPreferenceStore ??
        MacOSArchiveColumnPreferenceStore();
    _loadThemeMode();
    _loadSingleEntryExtractionMode();
    _loadArchiveColumnPreferences();
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

  Future<void> _loadSingleEntryExtractionMode() async {
    final mode = await _singleEntryExtractionPreferenceStore.load();
    if (mounted && !_singleEntryExtractionModeChangedByUser) {
      setState(() => _singleEntryExtractionMode = mode);
    }
  }

  void _setSingleEntryExtractionMode(SingleEntryExtractionMode mode) {
    if (_singleEntryExtractionMode == mode) return;
    _singleEntryExtractionModeChangedByUser = true;
    setState(() => _singleEntryExtractionMode = mode);
    _singleEntryExtractionPreferenceStore.save(mode);
  }

  Future<void> _loadArchiveColumnPreferences() async {
    final preferences = await _archiveColumnPreferenceStore.load();
    if (mounted && !_archiveColumnPreferencesChangedByUser) {
      setState(() => _archiveColumnPreferences = preferences);
    }
  }

  void _setArchiveColumnPreferences(ArchiveColumnPreferences preferences) {
    _archiveColumnPreferencesChangedByUser = true;
    setState(() => _archiveColumnPreferences = preferences);
    _archiveColumnPreferenceStore.save(preferences);
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
        singleEntryExtractionMode: _singleEntryExtractionMode,
        onSingleEntryExtractionModeChanged: _setSingleEntryExtractionMode,
        archiveColumnPreferences: _archiveColumnPreferences,
        onArchiveColumnPreferencesChanged: _setArchiveColumnPreferences,
      ),
    );
  }
}

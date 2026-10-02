import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'application/jucier_shell.dart';
import 'archive/archive_column.dart';
import 'archive/archive_engine.dart';
import 'archive/archive_options.dart';
import 'archive/seven_zip_engine.dart';
import 'platform/archive_file_association_service.dart';
import 'platform/archive_open_service.dart';
import 'platform/archive_open_preference_store.dart';
import 'platform/desktop_window_service.dart';
import 'platform/file_access_service.dart';
import 'platform/finder_action_service.dart';
import 'widgets/windows_title_bar.dart';
import 'platform/archive_column_preference_store.dart';
import 'platform/single_entry_extraction_preference_store.dart';
import 'platform/theme_preference_store.dart';
import 'platform/smart_extraction_preference_store.dart';
import 'platform/compression_preference_store.dart';

export 'application/jucier_shell.dart' show JucierShell;

final _lightDesktopTheme = _desktopTheme(FColors.neutralLight);
final _darkDesktopTheme = _desktopTheme(FColors.neutralDark);

FThemeData _desktopTheme(FColors colors) {
  final typeface = FTypeface.inherit(
    colors: colors,
    touch: false,
    fontFamily: 'HarmonyOS Sans SC',
  );
  // Construct the theme with typography so all component styles inherit it.
  // The Material mapping below uses the same typeface.
  return FThemeData(
    colors: colors,
    touch: false,
    typography: FTypography(display: typeface, body: typeface),
  );
}

/// Configures global theming and wires the app's platform dependencies.
class JucierApp extends StatefulWidget {
  const JucierApp({
    super.key,
    this.engine,
    this.fileAccessService,
    this.themePreferenceStore,
    this.compressionPreferenceStore,
    this.singleEntryExtractionPreferenceStore,
    this.archiveColumnPreferenceStore,
    this.archiveFileAssociationService,
    this.archiveOpenService,
    this.archiveOpenPreferenceStore,
    this.desktopWindowService,
    this.selectExternalExtractionDirectory,
    this.finderActionService,
    this.waitForInitialArchiveOpen = false,
  });

  final ArchiveEngine? engine;
  final FileAccessService? fileAccessService;
  final ThemePreferenceStore? themePreferenceStore;
  final CompressionPreferenceStore? compressionPreferenceStore;
  final SingleEntryExtractionPreferenceStore?
  singleEntryExtractionPreferenceStore;
  final ArchiveColumnPreferenceStore? archiveColumnPreferenceStore;
  final ArchiveFileAssociationService? archiveFileAssociationService;
  final ArchiveOpenService? archiveOpenService;
  final ArchiveOpenPreferenceStore? archiveOpenPreferenceStore;
  final DesktopWindowService? desktopWindowService;
  final Future<String?> Function()? selectExternalExtractionDirectory;
  final FinderActionService? finderActionService;
  final bool waitForInitialArchiveOpen;

  @override
  State<JucierApp> createState() => _JucierAppState();
}

class _JucierAppState extends State<JucierApp> {
  late final ArchiveEngine _engine;
  late final FileAccessService _fileAccessService;
  late final ThemePreferenceStore _themePreferenceStore;
  late final CompressionPreferenceStore _compressionPreferenceStore;
  CompressionPerformance _compressionPerformance =
      CompressionPerformance.balanced;
  bool _compressionChangedByUser = false;
  late final SingleEntryExtractionPreferenceStore
  _singleEntryExtractionPreferenceStore;
  late final ArchiveColumnPreferenceStore _archiveColumnPreferenceStore;
  late final ArchiveFileAssociationService _archiveFileAssociationService;
  late final ArchiveOpenService _archiveOpenService;
  late final ArchiveOpenPreferenceStore _archiveOpenPreferenceStore;
  late final Future<void> _externalOpenPreferencesReady;
  ArchiveOpenMode _archiveOpenMode = ArchiveOpenMode.open;
  bool _archiveOpenModeChangedByUser = false;
  late final FinderActionService _finderActionService;
  final _smartExtractionStore = DesktopSmartExtractionPreferenceStore();
  bool _smartExtractionEnabled = true;
  bool _smartExtractionChangedByUser = false;
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
    _fileAccessService = widget.fileAccessService ?? DesktopFileAccessService();
    _themePreferenceStore =
        widget.themePreferenceStore ?? DesktopThemePreferenceStore();
    _compressionPreferenceStore =
        widget.compressionPreferenceStore ??
        DesktopCompressionPreferenceStore();
    _singleEntryExtractionPreferenceStore =
        widget.singleEntryExtractionPreferenceStore ??
        DesktopSingleEntryExtractionPreferenceStore();
    _archiveColumnPreferenceStore =
        widget.archiveColumnPreferenceStore ??
        DesktopArchiveColumnPreferenceStore();
    _archiveFileAssociationService =
        widget.archiveFileAssociationService ??
        MacOSArchiveFileAssociationService();
    _archiveOpenService =
        widget.archiveOpenService ?? DesktopArchiveOpenService();
    _archiveOpenPreferenceStore =
        widget.archiveOpenPreferenceStore ??
        DesktopArchiveOpenPreferenceStore();
    _finderActionService =
        widget.finderActionService ?? DesktopFinderActionService();
    _externalOpenPreferencesReady = _loadExternalOpenPreferences();
    _loadCompressionPerformance();
    _loadThemeMode();
    _loadSingleEntryExtractionMode();
    _loadArchiveColumnPreferences();
  }

  Future<void> _loadExternalOpenPreferences() async {
    await Future.wait([_loadArchiveOpenMode(), _loadSmartExtraction()]);
  }

  Future<ArchiveOpenPreferences> _resolveExternalOpenPreferences() async {
    await _externalOpenPreferencesReady;
    // Read state directly: a native open event can arrive before the next
    // Flutter frame has passed these loaded values to the shell.
    return (
      mode: _archiveOpenMode,
      smartExtractionEnabled: _smartExtractionEnabled,
    );
  }

  Future<void> _loadArchiveOpenMode() async {
    final mode = await _archiveOpenPreferenceStore.load();
    if (mounted && !_archiveOpenModeChangedByUser) {
      setState(() => _archiveOpenMode = mode);
    }
  }

  void _setArchiveOpenMode(ArchiveOpenMode mode) {
    if (_archiveOpenMode == mode) return;
    _archiveOpenModeChangedByUser = true;
    setState(() => _archiveOpenMode = mode);
    _archiveOpenPreferenceStore.save(mode);
  }

  Future<void> _loadSmartExtraction() async {
    final enabled = await _smartExtractionStore.load();
    if (mounted && !_smartExtractionChangedByUser) {
      setState(() => _smartExtractionEnabled = enabled);
    }
  }

  Future<void> _loadCompressionPerformance() async {
    final performance = await _compressionPreferenceStore.load();
    if (mounted && !_compressionChangedByUser) {
      setState(() => _compressionPerformance = performance);
    }
  }

  void _setCompressionPerformance(CompressionPerformance performance) {
    if (_compressionPerformance == performance) return;
    _compressionChangedByUser = true;
    setState(() => _compressionPerformance = performance);
    _compressionPreferenceStore.save(performance);
  }

  void _setSmartExtraction(bool enabled) {
    _smartExtractionChangedByUser = true;
    setState(() => _smartExtractionEnabled = enabled);
    _smartExtractionStore.save(enabled);
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
    final light = _lightDesktopTheme;
    final dark = _darkDesktopTheme;

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
              child: Material(
                type: MaterialType.transparency,
                child:
                    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
                    ? Column(
                        children: [
                          const WindowsTitleBar(),
                          Expanded(child: child!),
                        ],
                      )
                    : child!,
              ),
            ),
          ),
        );
      },
      home: JucierShell(
        engine: _engine,
        fileAccessService: _fileAccessService,
        archiveFileAssociationService: _archiveFileAssociationService,
        archiveOpenService: _archiveOpenService,
        desktopWindowService:
            widget.desktopWindowService ?? const NativeDesktopWindowService(),
        selectExternalExtractionDirectory:
            widget.selectExternalExtractionDirectory,
        resolveExternalOpenPreferences: _resolveExternalOpenPreferences,
        archiveOpenMode: _archiveOpenMode,
        onArchiveOpenModeChanged: _setArchiveOpenMode,
        finderActionService: _finderActionService,
        waitForInitialArchiveOpen: widget.waitForInitialArchiveOpen,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        compressionPerformance: _compressionPerformance,
        onCompressionPerformanceChanged: _setCompressionPerformance,
        smartExtractionEnabled: _smartExtractionEnabled,
        onSmartExtractionChanged: _setSmartExtraction,
        singleEntryExtractionMode: _singleEntryExtractionMode,
        onSingleEntryExtractionModeChanged: _setSingleEntryExtractionMode,
        archiveColumnPreferences: _archiveColumnPreferences,
        onArchiveColumnPreferencesChanged: _setArchiveColumnPreferences,
      ),
    );
  }
}

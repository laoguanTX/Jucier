import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:path/path.dart' as p;

import '../archive/archive_engine.dart';
import '../archive/archive_entry.dart';
import '../archive/archive_column.dart';
import '../archive/archive_formats.dart';
import '../archive/archive_options.dart';
import '../archive/smart_extraction.dart';
import '../dialogs/confirmation_dialog.dart';
import '../dialogs/create_archive_dialog.dart';
import '../dialogs/extract_dialog.dart';
import '../dialogs/message_dialog.dart';
import '../dialogs/password_dialog.dart';
import '../platform/file_access_service.dart';
import '../platform/finder_action_service.dart';
import '../platform/archive_drag_service.dart';
import '../platform/archive_file_association_service.dart';
import '../platform/archive_open_service.dart';
import '../platform/archive_open_preference_store.dart';
import '../platform/desktop_window_service.dart';
import '../platform/file_preview_service.dart';
import '../platform/single_entry_extraction_preference_store.dart';
import '../screens/archive_screen.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/operation_progress.dart';
import '../widgets/external_operation_view.dart';
import 'archive_draft.dart';
import 'archive_workflow_controller.dart';
import 'settings_page_transition.dart';

/// Space reserved above Flutter content for the floating macOS traffic lights.
const double _macOSTrafficLightInset = 26;

bool get _isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Owns the single-window navigation state and coordinates archive workflows.
class JucierShell extends StatefulWidget {
  const JucierShell({
    required this.engine,
    required this.fileAccessService,
    required this.archiveFileAssociationService,
    required this.archiveOpenService,
    required this.finderActionService,
    this.waitForInitialArchiveOpen = false,
    this.resolveExternalOpenPreferences,
    this.desktopWindowService = const NativeDesktopWindowService(),
    this.selectExternalExtractionDirectory,
    this.archiveOpenMode = ArchiveOpenMode.open,
    this.onArchiveOpenModeChanged,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.compressionPerformance = CompressionPerformance.balanced,
    this.onCompressionPerformanceChanged,
    this.fileLauncher,
    this.singleEntryExtractionMode =
        SingleEntryExtractionMode.preserveArchiveStructure,
    this.onSingleEntryExtractionModeChanged,
    this.smartExtractionEnabled = true,
    this.onSmartExtractionChanged,
    this.archiveColumnPreferences = const ArchiveColumnPreferences(),
    this.onArchiveColumnPreferencesChanged,
    super.key,
  });

  final ArchiveEngine engine;
  final FileAccessService fileAccessService;
  final ArchiveFileAssociationService archiveFileAssociationService;
  final ArchiveOpenService archiveOpenService;
  final DesktopWindowService desktopWindowService;
  final Future<String?> Function()? selectExternalExtractionDirectory;
  final FinderActionService finderActionService;
  final bool waitForInitialArchiveOpen;
  final Future<ArchiveOpenPreferences> Function()?
  resolveExternalOpenPreferences;
  final ArchiveOpenMode archiveOpenMode;
  final ValueChanged<ArchiveOpenMode>? onArchiveOpenModeChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final CompressionPerformance compressionPerformance;
  final ValueChanged<CompressionPerformance>? onCompressionPerformanceChanged;
  final FileLauncher? fileLauncher;
  final bool smartExtractionEnabled;
  final ValueChanged<bool>? onSmartExtractionChanged;
  final SingleEntryExtractionMode singleEntryExtractionMode;
  final ValueChanged<SingleEntryExtractionMode>?
  onSingleEntryExtractionModeChanged;
  final ArchiveColumnPreferences archiveColumnPreferences;
  final ValueChanged<ArchiveColumnPreferences>?
  onArchiveColumnPreferencesChanged;

  @override
  State<JucierShell> createState() => _JucierShellState();
}

class _JucierShellState extends State<JucierShell> {
  late final ArchiveWorkflowController _workflow;
  late final FilePreviewService _previews;
  late final MacOSArchiveDragService _archiveDragService;
  final Map<String, _ArchiveDragPayload> _dragPayloads = {};
  int _nextDragId = 0;
  Future<void> _previewPromptQueue = Future.value();
  late bool _checkingForExternalArchive;
  bool _openingExternalArchive = false;
  bool _externalArchiveSession = false;
  bool _settingsOpen = false;
  bool _creatingArchive = false;
  bool _draftLoading = false;
  bool _compactOperation = false;
  bool _externalOnlySession = false;
  String _externalOperationTitle = '';
  String? _externalOperationMessage;
  bool _externalOperationFailed = false;
  bool _externalOperationCancelled = false;
  Completer<void>? _externalResultClosed;
  Future<void> _externalOperationQueue = Future.value();
  int _draftGeneration = 0;
  List<String> _draftSources = [];
  ArchiveListing _draftListing = const ArchiveListing(
    archivePath: '新建压缩包',
    entries: [],
    physicalSize: 0,
  );

  @override
  void initState() {
    super.initState();
    _checkingForExternalArchive = widget.waitForInitialArchiveOpen;
    _workflow = ArchiveWorkflowController(
      widget.engine,
      compressionPerformance: () => widget.compressionPerformance,
    );
    _previews = FilePreviewService(
      launcher: widget.fileLauncher ?? DesktopFileLauncher(),
      onChanged: _handlePreviewChanged,
    );
    _archiveDragService = MacOSArchiveDragService(
      onMaterialize: _materializeDraggedEntry,
    );
    widget.fileAccessService.setOpenSettingsHandler(_openSettings);
    widget.archiveOpenService.setHandler(_openExternalArchive);
    widget.finderActionService.setHandler(_handleFinderAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_synchronizeExternalOpenRequests());
      unawaited(_requestInitialAccess());
    });
  }

  @override
  void dispose() {
    widget.fileAccessService.setOpenSettingsHandler(null);
    widget.archiveOpenService.setHandler(null);
    widget.finderActionService.setHandler(null);
    if (_externalResultClosed?.isCompleted == false) {
      _externalResultClosed!.complete();
    }
    unawaited(_previews.dispose());
    _archiveDragService.dispose();
    _workflow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _workflow,
    builder: (context, _) => Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            const _OpenSettingsIntent(),
        if (!_isMacOS)
          const SingleActivator(LogicalKeyboardKey.comma, control: true):
              const _OpenSettingsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
            onInvoke: (_) {
              _openSettings();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: FScaffold(
            childPad: false,
            footer: _compactOperation || _workflow.operationLabel == null
                ? null
                : ValueListenableBuilder<double?>(
                    valueListenable: _workflow.progressChanges,
                    builder: (context, progress, _) => OperationProgress(
                      label: _workflow.operationLabel ?? '正在完成',
                      progress: progress,
                      onCancel: _workflow.cancel,
                    ),
                  ),
            child: Padding(
              key: const ValueKey('window-content-padding'),
              padding: EdgeInsets.only(
                top: _isMacOS ? _macOSTrafficLightInset : 0,
              ),
              child: _compactOperation
                  ? ValueListenableBuilder<double?>(
                      valueListenable: _workflow.progressChanges,
                      builder: (context, progress, _) => ExternalOperationView(
                        key: const ValueKey('external-operation-window'),
                        title: _externalOperationTitle,
                        label: _workflow.operationLabel ?? '正在准备',
                        progress: _workflow.busy ? progress : 0,
                        message: _externalOperationMessage,
                        failed: _externalOperationFailed,
                        onCancel: _cancelExternalOperation,
                        onClose: () {
                          if (_externalResultClosed?.isCompleted == false) {
                            _externalResultClosed!.complete();
                          }
                        },
                      ),
                    )
                  : SettingsPageTransition(child: _buildCurrentPage()),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildCurrentPage() {
    if (_checkingForExternalArchive || _openingExternalArchive) {
      return const SizedBox.expand(
        key: ValueKey('external-archive-launch-page'),
      );
    }
    if (_settingsOpen) {
      return SettingsScreen(
        key: const ValueKey('settings-page'),
        fileAccessService: widget.fileAccessService,
        archiveFileAssociationService: widget.archiveFileAssociationService,
        finderActionService: widget.finderActionService,
        archiveOpenMode: widget.archiveOpenMode,
        onArchiveOpenModeChanged: widget.onArchiveOpenModeChanged,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        compressionPerformance: widget.compressionPerformance,
        onCompressionPerformanceChanged: widget.onCompressionPerformanceChanged,
        smartExtractionEnabled: widget.smartExtractionEnabled,
        onSmartExtractionChanged: widget.onSmartExtractionChanged,
        singleEntryExtractionMode: widget.singleEntryExtractionMode,
        onSingleEntryExtractionModeChanged:
            widget.onSingleEntryExtractionModeChanged,
        archiveColumnPreferences: widget.archiveColumnPreferences,
        onArchiveColumnPreferencesChanged:
            widget.onArchiveColumnPreferencesChanged,
        onBack: () => setState(() => _settingsOpen = false),
      );
    }
    if (_creatingArchive) {
      return ArchiveScreen(
        key: const ValueKey('archive-compose-page'),
        listing: _draftListing,
        enabled: !_workflow.busy && !_draftLoading,
        mode: ArchiveScreenMode.compose,
        columns: widget.archiveColumnPreferences.compressionColumns,
        onClose: _closeArchiveDraft,
        onExtract: () {},
        onTest: () {},
        onPreviewEntry: (_) {},
        onExtractEntry: (_) {},
        onDeleteEntry: (_) {},
        onExtractEntries: (_) async => false,
        onDeleteEntries: (_) async => false,
        onImport: (_) => _pickDraftSources(),
        onCreate: _createDraftArchive,
        onDropped: (paths, _) => _addDraftSources(paths),
        onDragEntries: (_) async {},
      );
    }
    if (_workflow.listing == null) {
      return HomeScreen(
        key: const ValueKey('home-page'),
        enabled: !_workflow.busy,
        onOpen: _pickArchive,
        onCreate: _startArchiveDraft,
        onSettings: _openSettings,
        onDropped: _handleDroppedPaths,
      );
    }
    return ArchiveScreen(
      key: const ValueKey('archive-page'),
      listing: _workflow.listing!,
      enabled: !_workflow.busy,
      columns: widget.archiveColumnPreferences.extractionColumns,
      onClose: _closeOpenArchive,
      onExtract: _extractCurrentArchive,
      onTest: _testCurrentArchive,
      onPreviewEntry: _previewEntry,
      onExtractEntry: _extractEntry,
      onDeleteEntry: _deleteEntry,
      onExtractEntries: _extractEntries,
      onDeleteEntries: _deleteEntries,
      onImport: _pickEntriesToAdd,
      onOptimize: _optimizeCurrentArchive,
      onManagePreviews: _previews.sessions.isEmpty ? null : _managePreviews,
      onDropped: _addDroppedEntries,
      onDragEntries: _isMacOS ? _dragEntries : null,
    );
  }

  void _openSettings() {
    if (mounted && !_compactOperation) {
      setState(() => _settingsOpen = true);
      unawaited(widget.desktopWindowService.showMainWindow());
    }
  }

  Future<void> _synchronizeExternalOpenRequests() async {
    // Drain contextual actions first so cold quick actions never show Home.
    await widget.finderActionService.synchronize();
    await widget.archiveOpenService.synchronize();
    if (mounted) setState(() => _checkingForExternalArchive = false);
    if (mounted && !_externalOnlySession && !_compactOperation) {
      await _revealMainWindow(explicit: false);
    }
  }

  Future<void> _revealMainWindow({bool explicit = true}) async {
    await _prepareWindowFrame();
    if (mounted) {
      await widget.desktopWindowService.showMainWindow(explicit: explicit);
    }
  }

  Future<void> _prepareWindowFrame() async {
    // Hidden/minimized desktop windows may stop receiving vsync. Build the
    // selected view without waiting for a native frame that requires visibility.
    WidgetsBinding.instance.scheduleWarmUpFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _runExternalOperation(
    String title,
    Future<void> Function() action,
  ) {
    final previous = _externalOperationQueue;
    final operation = () async {
      await previous;
      await _workflow.waitUntilIdle();
      if (!mounted) return;
      final compact = await widget.desktopWindowService.prepareOperation();
      if (!mounted) return;
      _externalOperationCancelled = false;
      if (compact) {
        setState(() {
          _compactOperation = true;
          _externalOperationTitle = title;
          _externalOperationMessage = null;
          _externalOperationFailed = false;
        });
        await _prepareWindowFrame();
        if (!mounted) return;
        await widget.desktopWindowService.showPreparedWindow();
      }
      try {
        await action();
      } on FileSystemException catch (error) {
        await _showExternalOperationResult(
          title: '$title失败',
          message: error.message,
          failed: true,
        );
      } finally {
        if (compact && mounted) {
          final quit = await widget.desktopWindowService.finishOperation();
          if (quit) {
            _externalOnlySession = true;
            await widget.archiveOpenService.quitApplication();
          } else {
            setState(() => _compactOperation = false);
          }
        }
      }
    }();
    _externalOperationQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _cancelExternalOperation() async {
    _externalOperationCancelled = true;
    await _workflow.cancel();
  }

  Future<void> _requestInitialAccess() async {
    final status = await widget.fileAccessService.status();
    if (!status.requested && mounted) {
      await widget.fileAccessService.requestAccess();
    }
  }

  Future<void> _pickArchive() async {
    const archiveTypes = XTypeGroup(
      label: '压缩文件',
      extensions: supportedArchiveExtensions,
    );
    final file = await openFile(
      acceptedTypeGroups: const [archiveTypes],
      confirmButtonText: '打开',
    );
    if (file != null) await _openArchive(file.path);
  }

  void _startArchiveDraft() {
    setState(() {
      _creatingArchive = true;
      _draftLoading = false;
      _draftGeneration++;
      _draftSources = [];
      _draftListing = const ArchiveListing(
        archivePath: '新压缩包',
        entries: [],
        physicalSize: 0,
      );
    });
  }

  void _closeArchiveDraft() {
    setState(() {
      _creatingArchive = false;
      _draftLoading = false;
      _draftGeneration++;
      _draftSources = [];
    });
  }

  Future<void> _pickDraftSources() async {
    final choice = await showSourcePicker(
      context,
      title: '导入到新压缩包',
      description: '选择要压缩的文件或文件夹',
    );
    if (!mounted || choice == null) return;

    final List<String> paths;
    if (choice == SourcePickerChoice.files) {
      paths = (await openFiles(confirmButtonText: '导入'))
          .map((file) => file.path)
          .toList();
    } else {
      final path = await getDirectoryPath(confirmButtonText: '导入文件夹');
      paths = [?path];
    }
    if (paths.isNotEmpty && mounted) await _addDraftSources(paths);
  }

  Future<void> _addDraftSources(List<String> paths) async {
    if (paths.isEmpty || _draftLoading) return;
    final nextSources = List<String>.of(_draftSources);
    for (final path in paths) {
      if (!nextSources.any((existing) => p.equals(existing, path))) {
        nextSources.add(path);
      }
    }
    final generation = ++_draftGeneration;
    final previous = _draftListing;
    final added = nextSources
        .where((source) => !_draftSources.contains(source))
        .toList();
    setState(() => _draftLoading = true);
    try {
      final increment = await buildArchiveDraftListing(added);
      final listing = ArchiveListing(
        archivePath: previous.archivePath,
        entries: [...previous.entries, ...increment.entries],
        physicalSize:
            (previous.physicalSize ?? 0) + (increment.physicalSize ?? 0),
      );
      if (!mounted || !_creatingArchive || generation != _draftGeneration) {
        return;
      }
      setState(() {
        _draftSources = nextSources;
        _draftListing = listing;
      });
    } on FileSystemException catch (error) {
      if (mounted) {
        await showMessageDialog(
          context,
          title: '无法导入',
          message: error.message,
          details: error.toString(),
        );
      }
    } finally {
      if (mounted && generation == _draftGeneration) {
        setState(() => _draftLoading = false);
      }
    }
  }

  Future<void> _handleDroppedPaths(List<String> paths) async {
    if (_workflow.busy || paths.isEmpty) return;
    if (paths.length == 1 && isSupportedArchivePath(paths.single)) {
      await _openArchive(paths.single);
    } else {
      _startArchiveDraft();
      await _addDraftSources(paths);
    }
  }

  Future<void> _openArchive(String path, {String? password}) async {
    try {
      await _workflow.open(path, password: password);
    } on ArchivePasswordRequiredException {
      if (!mounted) return;
      final entered = await showPasswordDialog(context, title: '输入压缩包密码');
      if (entered != null && mounted) {
        await _openArchive(path, password: entered);
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '无法打开', error: error);
      }
    }
  }

  Future<void> _openExternalArchive(String path) async {
    if (!isSupportedArchivePath(path)) return;
    final preferences = await _externalOpenPreferences();
    if (!mounted) return;
    await _workflow.waitUntilIdle();
    if (!mounted) return;
    if (preferences.mode == ArchiveOpenMode.extract) {
      await _runExternalOperation(
        '解压文件',
        () => _extractArchivesBesideSource([
          path,
        ], smartExtractionEnabled: preferences.smartExtractionEnabled),
      );
      return;
    }
    setState(() {
      _openingExternalArchive = true;
      _externalArchiveSession = true;
      _settingsOpen = false;
      _creatingArchive = false;
      _draftLoading = false;
      _draftGeneration++;
      _draftSources = [];
    });
    await _openArchive(path);
    if (!mounted) return;
    if (_workflow.listing?.archivePath != path) {
      await widget.archiveOpenService.quitApplication();
      return;
    }
    setState(() => _openingExternalArchive = false);
    await _revealMainWindow();
  }

  Future<ArchiveOpenPreferences> _externalOpenPreferences() async =>
      await widget.resolveExternalOpenPreferences?.call() ??
      (
        mode: widget.archiveOpenMode,
        smartExtractionEnabled: widget.smartExtractionEnabled,
      );

  Future<void> _handleFinderAction(FinderActionRequest request) async {
    await _workflow.waitUntilIdle();
    if (!mounted) return;

    switch (request.type) {
      case FinderActionType.extractHere:
        final preferences = await _externalOpenPreferences();
        if (!mounted) return;
        await _runExternalOperation(
          '解压文件',
          () => _extractArchivesBesideSource(
            request.paths,
            smartExtractionEnabled: preferences.smartExtractionEnabled,
          ),
        );
      case FinderActionType.extractTo:
        final preferences = await _externalOpenPreferences();
        if (!mounted) return;
        await _runExternalOperation('解压文件', () async {
          final directory =
              await (widget.selectExternalExtractionDirectory?.call() ??
                  getDirectoryPath(confirmButtonText: '解压到这里'));
          if (!mounted) return;
          if (directory == null) {
            await _showExternalOperationResult(
              title: '解压已取消',
              message: '操作已取消。',
            );
            return;
          }
          await _extractArchivesBesideSource(
            request.paths,
            smartExtractionEnabled: preferences.smartExtractionEnabled,
            outputDirectory: directory,
          );
        });
      case FinderActionType.compressZip:
        await _runExternalOperation(
          '压缩文件',
          () => _compressFinderSourcesToZip(request.paths),
        );
      case FinderActionType.compress:
        await _runExternalOperation(
          '压缩文件',
          () => _configureExternalArchive(request.paths),
        );
    }
  }

  Future<void> _extractArchivesBesideSource(
    List<String> paths, {
    required bool smartExtractionEnabled,
    String? outputDirectory,
  }) async {
    final archives = paths.where(isSupportedArchivePath).toList();

    if (archives.isEmpty) {
      await _showExternalOperationResult(
        title: '解压失败',
        message: '所选项目中没有支持的压缩包。',
        failed: true,
      );
      return;
    }

    var completed = 0;
    _ArchiveExtractionOutcome? stopped;
    String? completedDirectory;
    for (final archivePath in archives) {
      if (!mounted) return;
      final outcome = await _extractArchiveBesideSource(
        archivePath,
        smartExtractionEnabled: smartExtractionEnabled,
        outputDirectory: outputDirectory,
      );
      if (!outcome.succeeded) {
        stopped = outcome;
        break;
      }
      completed++;
      completedDirectory = outcome.outputDirectory;
    }

    if (!mounted) return;
    if (stopped != null) {
      final prefix = completed == 0 ? '' : '已成功解压 $completed 个压缩包。\n\n';
      await _showExternalOperationResult(
        title: stopped.cancelled ? '解压已取消' : '解压失败',
        message: '$prefix${p.basename(stopped.archivePath)}：${stopped.error}',
        failed: !stopped.cancelled,
      );
      return;
    }

    await _showExternalOperationResult(
      title: '解压完成',
      message: completed == 1
          ? '文件已保存到 $completedDirectory'
          : outputDirectory == null
          ? '$completed 个压缩包已解压到各自所在位置。'
          : '$completed 个压缩包已保存到 $outputDirectory。',
    );
  }

  Future<void> _showExternalOperationResult({
    required String title,
    required String message,
    bool failed = false,
  }) async {
    if (!mounted) return;
    if (_compactOperation) {
      final closed = Completer<void>();
      _externalResultClosed = closed;
      setState(() {
        _externalOperationTitle = title;
        _externalOperationMessage = message;
        _externalOperationFailed = failed;
      });
      await closed.future;
      _externalResultClosed = null;
    } else {
      await showMessageDialog(context, title: title, message: message);
    }
  }

  Future<_ArchiveExtractionOutcome> _extractArchiveBesideSource(
    String archivePath, {
    required bool smartExtractionEnabled,
    String? outputDirectory,
    String? password,
  }) async {
    try {
      final destination = smartExtractionEnabled
          ? smartExtractionDirectory(
              await widget.engine.list(archivePath, password: password),
              outputDirectory ?? p.dirname(archivePath),
            )
          : outputDirectory ?? p.dirname(archivePath);
      if (_externalOperationCancelled) throw const ArchiveCancelledException();
      await _workflow.extract(
        ExtractArchiveOptions(
          archivePath: archivePath,
          outputDirectory: destination,
          password: password,
        ),
      );
      return _ArchiveExtractionOutcome.succeeded(archivePath, destination);
    } on ArchivePasswordRequiredException {
      if (!mounted) {
        return _ArchiveExtractionOutcome.failed(archivePath, '应用已关闭。');
      }
      final entered = await showPasswordDialog(
        context,
        title: '输入 ${p.basename(archivePath)} 的密码',
      );
      if (entered == null || !mounted) {
        return _ArchiveExtractionOutcome.cancelled(archivePath);
      }
      return _extractArchiveBesideSource(
        archivePath,
        smartExtractionEnabled: smartExtractionEnabled,
        outputDirectory: outputDirectory,
        password: entered,
      );
    } on ArchiveCancelledException {
      return _ArchiveExtractionOutcome.cancelled(archivePath);
    } on ArchiveException catch (error) {
      return _ArchiveExtractionOutcome.failed(archivePath, error.message);
    }
  }

  Future<List<String>> _existingSources(List<String> paths) async {
    final sources = <String>[];
    for (final path in paths) {
      if (!sources.any((existing) => p.equals(existing, path)) &&
          await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        sources.add(path);
      }
    }
    if (sources.isEmpty && mounted) {
      await _showExternalOperationResult(
        title: '压缩失败',
        message: '所选文件已不存在。',
        failed: true,
      );
    }
    return sources;
  }

  Future<void> _configureExternalArchive(List<String> paths) async {
    final sources = await _existingSources(paths);
    if (!mounted || sources.isEmpty) return;
    if (_compactOperation) {
      await widget.desktopWindowService.configureOperationWindow(true);
    }
    if (!mounted) return;
    final options = await showCreateArchiveDialog(context, sources: sources);
    if (!mounted) return;
    if (_compactOperation) {
      await widget.desktopWindowService.configureOperationWindow(false);
    }
    if (options == null) {
      await _showExternalOperationResult(title: '压缩已取消', message: '操作已取消。');
      return;
    }
    if (!await _confirmArchiveReplacement(options) || !mounted) {
      await _showExternalOperationResult(title: '压缩已取消', message: '操作已取消。');
      return;
    }
    await _createExternalArchive(options);
  }

  Future<void> _compressFinderSourcesToZip(List<String> paths) async {
    final sources = await _existingSources(paths);
    if (!mounted || sources.isEmpty) return;
    final archivePath = await _availableZipPath(sources);

    await _createExternalArchive(
      CreateArchiveOptions(
        archivePath: archivePath,
        sources: sources,
        format: ArchiveFormat.zip,
      ),
    );
  }

  Future<void> _createExternalArchive(CreateArchiveOptions options) async {
    try {
      if (_externalOperationCancelled) throw const ArchiveCancelledException();
      await _workflow.create(options, openAfterCreate: false);
      await _showExternalOperationResult(
        title: '压缩完成',
        message: '压缩包已保存到 ${options.archivePath}',
      );
    } on ArchiveCancelledException {
      await _showExternalOperationResult(title: '压缩已取消', message: '操作已取消。');
    } on ArchiveException catch (error) {
      await _showExternalOperationResult(
        title: error is ArchiveWarningException ? '部分完成' : '压缩失败',
        message: error.message,
        failed: true,
      );
    }
  }

  Future<bool> _confirmArchiveReplacement(CreateArchiveOptions options) async {
    if (!await File(options.archivePath).exists() &&
        !await File('${options.archivePath}.001').exists()) {
      return true;
    }
    if (!mounted) return false;
    return showConfirmationDialog(
      context,
      title: '替换已有压缩包？',
      message: '新压缩包将替换 ${p.basename(options.archivePath)}，旧包中的其他文件不会保留。',
      confirmLabel: '替换',
      destructive: true,
    );
  }

  Future<String> _availableZipPath(List<String> sources) async {
    final directory = p.dirname(sources.first);
    var baseName = 'Archive';
    if (sources.length == 1) {
      final source = sources.first;
      final sourceType = await FileSystemEntity.type(source);
      baseName = sourceType == FileSystemEntityType.directory
          ? p.basename(source)
          : p.basenameWithoutExtension(source);
    }
    var candidate = p.join(directory, '$baseName.zip');
    for (
      var suffix = 2;
      await FileSystemEntity.type(candidate) != FileSystemEntityType.notFound;
      suffix++
    ) {
      candidate = p.join(directory, '$baseName $suffix.zip');
    }
    return candidate;
  }

  void _closeOpenArchive() {
    if (_externalArchiveSession) {
      unawaited(widget.archiveOpenService.quitApplication());
      return;
    }
    _workflow.closeArchive();
  }

  Future<void> _createDraftArchive() async {
    if (_draftSources.isEmpty || _workflow.busy) return;
    final options = await showCreateArchiveDialog(
      context,
      sources: _draftSources,
    );
    if (options == null || !mounted) return;

    try {
      if (!await _confirmArchiveReplacement(options) || !mounted) return;
      await _workflow.create(options);
      if (mounted) {
        setState(() {
          _creatingArchive = false;
          _draftLoading = false;
          _draftGeneration++;
          _draftSources = [];
        });
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '压缩失败', error: error);
      }
    }
  }

  Future<void> _extractCurrentArchive() async {
    final listing = _workflow.listing;
    if (listing == null) return;
    final options = await showExtractDialog(
      context,
      archivePath: listing.archivePath,
      initialPassword: _workflow.password,
    );
    if (options == null || !mounted) return;

    try {
      final destination = widget.smartExtractionEnabled
          ? smartExtractionDirectory(listing, options.outputDirectory)
          : options.outputDirectory;
      var password = options.password;
      while (true) {
        try {
          await _workflow.extract(
            ExtractArchiveOptions(
              archivePath: options.archivePath,
              outputDirectory: destination,
              conflict: options.conflict,
              password: password,
            ),
          );
          break;
        } on ArchivePasswordRequiredException {
          if (!mounted) return;
          password = await showPasswordDialog(context, title: '输入压缩包密码');
          if (password == null || !mounted) return;
          if (_workflow.listing?.archivePath == options.archivePath) {
            _workflow.rememberPassword(password);
          }
        }
      }
      if (mounted) {
        await showMessageDialog(
          context,
          title: '解压完成',
          message: '文件已保存到 $destination',
        );
      }
    } on ArchivePasswordRequiredException {
      if (mounted) {
        await showMessageDialog(context, title: '密码错误', message: '请检查密码后重试。');
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '解压失败', error: error);
      }
    }
  }

  Future<void> _testCurrentArchive() async {
    final listing = _workflow.listing;
    if (listing == null) return;
    try {
      await _withArchivePassword(() => _workflow.testCurrent());
      if (mounted) {
        await showMessageDialog(context, title: '测试完成', message: '没有发现错误。');
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '测试失败', error: error);
      }
    }
  }

  Future<void> _managePreviews() async {
    final selected = await showFDialog<PreviewSession>(
      context: context,
      builder: (context, _, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(
          minWidth: 380,
          maxWidth: 460,
          maxHeight: 500,
        ),
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('关闭预览会话', style: style.titleTextStyle),
                const SizedBox(height: 12),
                for (final session in _previews.sessions)
                  FButton(
                    variant: FButtonVariant.ghost,
                    onPress: () => Navigator.of(context).pop(session),
                    child: Text(
                      '${p.basename(session.archivePath)} / ${session.entryPath}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final close = await showConfirmationDialog(
      context,
      title: '关闭此预览会话？',
      message: '请先在编辑器中保存，并将需要的修改应用到压缩包。关闭会删除此会话的临时文件。',
      confirmLabel: '关闭会话',
    );
    if (close) {
      await _previews.close(selected);
      if (mounted) setState(() {});
    }
  }

  Future<void> _withArchivePassword(Future<void> Function() action) async {
    final archivePath = _workflow.listing?.archivePath;
    while (true) {
      try {
        await action();
        return;
      } on ArchivePasswordRequiredException {
        if (!mounted) throw const ArchiveCancelledException();
        final password = await showPasswordDialog(context, title: '输入压缩包密码');
        if (password == null || !mounted) {
          throw const ArchiveCancelledException();
        }
        if (_workflow.listing?.archivePath != archivePath) {
          throw const ArchiveCancelledException();
        }
        _workflow.rememberPassword(password);
      }
    }
  }

  Future<void> _extractWithPassword(ExtractEntriesOptions options) async {
    var password = options.password;
    while (true) {
      try {
        await _workflow.extractEntries(
          ExtractEntriesOptions(
            archivePath: options.archivePath,
            entryPaths: options.entryPaths,
            outputDirectory: options.outputDirectory,
            password: password,
            conflict: options.conflict,
            withoutParentDirectories: options.withoutParentDirectories,
            selectedEntryPath: options.selectedEntryPath,
            selectedEntryPaths: options.selectedEntryPaths,
            outputPath: options.outputPath,
          ),
        );
        return;
      } on ArchivePasswordRequiredException {
        if (!mounted) throw const ArchiveCancelledException();
        password = await showPasswordDialog(context, title: '输入压缩包密码');
        if (password == null || !mounted) {
          throw const ArchiveCancelledException();
        }
        if (_workflow.listing?.archivePath == options.archivePath) {
          _workflow.rememberPassword(password);
        }
      }
    }
  }

  Future<void> _optimizeCurrentArchive() async {
    final listing = _workflow.listing;
    if (listing == null || !listing.canOptimize || _workflow.busy) return;
    final confirmed = await showConfirmationDialog(
      context,
      title: '整理压缩包？',
      message: '这会解压并重新压缩整个压缩包，可能耗时较长，并需要容纳解压内容的临时空间。将使用标准压缩等级重新生成固实压缩包。',
      confirmLabel: '开始整理',
    );
    if (!confirmed || !mounted) return;
    try {
      await _withArchivePassword(
        () => _workflow.addEntries(
          AddEntriesOptions(
            archivePath: listing.archivePath,
            sources: const [],
            destinationDirectory: '',
            password: _workflow.password,
            recompress: true,
          ),
        ),
      );
    } on ArchiveCancelledException {
      return;
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '整理未完成', error: error);
      }
    }
  }

  Future<void> _previewEntry(ArchiveEntry entry) async {
    final listing = _workflow.listing;
    if (listing == null || entry.isDirectory || _workflow.busy) return;
    try {
      final session = await _previews.open(
        archivePath: listing.archivePath,
        entryPath: entry.path,
        password: _workflow.password,
        preserveArchiveStructure:
            widget.singleEntryExtractionMode ==
            SingleEntryExtractionMode.preserveArchiveStructure,
        extract: (outputDirectory) => _extractWithPassword(
          ExtractEntriesOptions(
            archivePath: listing.archivePath,
            entryPaths: [entry.path],
            outputDirectory: outputDirectory,
            password: _workflow.password,
            withoutParentDirectories:
                widget.singleEntryExtractionMode ==
                SingleEntryExtractionMode.selectedOnly,
            selectedEntryPath: entry.path,
          ),
        ),
      );
      session.password = _workflow.password;
      if (mounted) setState(() {});
    } on ArchivePasswordRequiredException {
      if (mounted) {
        await showMessageDialog(context, title: '无法预览', message: '压缩包密码不正确。');
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '无法预览', error: error);
      }
    }
  }

  Future<void> _addDroppedEntries(List<String> paths, String directory) async {
    final listing = _workflow.listing;
    if (listing == null ||
        _workflow.busy ||
        _archiveDragService.dragInProgress ||
        paths.isEmpty) {
      return;
    }
    try {
      await _withArchivePassword(
        () => _workflow.addEntries(
          AddEntriesOptions(
            archivePath: listing.archivePath,
            sources: paths,
            destinationDirectory: directory,
            password: _workflow.password,
          ),
        ),
      );
      if (mounted) {
        await showMessageDialog(
          context,
          title: '添加完成',
          message:
              '${paths.length} 个项目已添加到${directory.isEmpty ? '压缩包根目录' : '/$directory'}。',
        );
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '添加失败', error: error);
      }
    }
  }

  Future<void> _pickEntriesToAdd(String directory) async {
    if (_workflow.busy) return;
    final choice = await showSourcePicker(
      context,
      title: '导入到压缩包',
      description: directory.isEmpty
          ? '选择要导入到根目录的内容'
          : '选择要导入到 /$directory 的内容',
    );
    if (!mounted || choice == null) return;

    final List<String> paths;
    if (choice == SourcePickerChoice.files) {
      paths = (await openFiles(confirmButtonText: '导入'))
          .map((file) => file.path)
          .toList();
    } else {
      final path = await getDirectoryPath(confirmButtonText: '导入文件夹');
      paths = [?path];
    }
    if (paths.isNotEmpty && mounted) {
      await _addDroppedEntries(paths, directory);
    }
  }

  Future<void> _dragEntries(List<ArchiveEntry> requestedEntries) async {
    final listing = _workflow.listing;
    if (listing == null || _workflow.busy || requestedEntries.isEmpty) return;
    final entries = _topLevelEntries(requestedEntries);
    final batch = DateTime.now().microsecondsSinceEpoch;
    final ids = <String>[];
    final items = <ArchiveDragItem>[];
    for (final entry in entries) {
      final id = '$batch-${_nextDragId++}';
      ids.add(id);
      _dragPayloads[id] = _ArchiveDragPayload(
        archivePath: listing.archivePath,
        password: _workflow.password,
        entry: entry,
        entryPaths: _pathsForEntry(listing, entry),
      );
      items.add(
        ArchiveDragItem(
          id: id,
          name: entry.name,
          isDirectory: entry.isDirectory,
        ),
      );
    }

    try {
      await _archiveDragService.beginDrag(items);
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '无法拖出文件', error: error);
      }
    } finally {
      for (final id in ids) {
        _dragPayloads.remove(id);
      }
    }
  }

  Future<void> _materializeDraggedEntry(
    ArchiveDragMaterializationRequest request,
  ) async {
    final payload = _dragPayloads[request.id];
    if (payload == null) throw const ArchiveException('拖拽项目已失效');
    await _workflow.waitUntilIdle();
    await _extractWithPassword(
      ExtractEntriesOptions(
        archivePath: payload.archivePath,
        entryPaths: payload.entryPaths,
        outputDirectory: p.dirname(request.outputPath),
        outputPath: request.outputPath,
        password: payload.password,
        withoutParentDirectories: true,
        selectedEntryPath: payload.entry.path,
      ),
    );
  }

  Future<void> _extractEntry(ArchiveEntry entry) async {
    await _extractEntries([entry]);
  }

  Future<bool> _extractEntries(List<ArchiveEntry> requestedEntries) async {
    final listing = _workflow.listing;
    if (listing == null || _workflow.busy || requestedEntries.isEmpty) {
      return false;
    }
    final entries = _topLevelEntries(requestedEntries);
    final outputDirectory = await getDirectoryPath(confirmButtonText: '解压到这里');
    if (outputDirectory == null || !mounted) return false;

    try {
      if (widget.singleEntryExtractionMode ==
          SingleEntryExtractionMode.selectedOnly) {
        await _extractWithPassword(
          ExtractEntriesOptions(
            archivePath: listing.archivePath,
            entryPaths: entries
                .expand((entry) => _pathsForEntry(listing, entry))
                .toSet()
                .toList(),
            selectedEntryPaths: entries.map((entry) => entry.path).toList(),
            outputDirectory: outputDirectory,
            password: _workflow.password,
            withoutParentDirectories: true,
            conflict: entries.length > 1
                ? ExtractionConflict.rename
                : ExtractionConflict.overwrite,
          ),
        );
      } else {
        final paths = entries
            .expand((entry) => _pathsForEntry(listing, entry))
            .toSet()
            .toList();
        await _extractWithPassword(
          ExtractEntriesOptions(
            archivePath: listing.archivePath,
            entryPaths: paths,
            outputDirectory: outputDirectory,
            password: _workflow.password,
          ),
        );
      }
      if (mounted) {
        final label = entries.length == 1
            ? entries.single.name
            : '${entries.length} 个项目';
        await showMessageDialog(
          context,
          title: '解压完成',
          message: '$label 已保存到 $outputDirectory',
        );
      }
      return true;
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
      return false;
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '解压失败', error: error);
      }
      return false;
    }
  }

  Future<void> _deleteEntry(ArchiveEntry entry) async {
    await _deleteEntries([entry]);
  }

  Future<bool> _deleteEntries(List<ArchiveEntry> requestedEntries) async {
    final listing = _workflow.listing;
    if (listing == null || _workflow.busy || requestedEntries.isEmpty) {
      return false;
    }
    final entries = _topLevelEntries(requestedEntries);
    final description = entries.length == 1
        ? '“${entries.single.name}”'
        : '所选 ${entries.length} 个项目';
    final confirmed = await showConfirmationDialog(
      context,
      title: '从压缩包中删除？',
      message: '$description将从 ${p.basename(listing.archivePath)} 中永久删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return false;

    try {
      final paths = entries
          .expand((entry) => _pathsForEntry(listing, entry))
          .toSet()
          .toList();
      await _withArchivePassword(() => _workflow.deleteEntries(paths));
      return true;
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
      return false;
    } on ArchiveException catch (error) {
      if (mounted) {
        await showArchiveErrorDialog(context, title: '删除失败', error: error);
      }
      return false;
    }
  }

  Future<void> _handlePreviewChanged(PreviewSession session) async {
    final queued = _previewPromptQueue.then(
      (_) => _processPreviewChange(session),
    );
    _previewPromptQueue = queued.onError((_, _) {});
    await queued;
  }

  Future<void> _processPreviewChange(PreviewSession session) async {
    if (!mounted) return;
    final apply = await showConfirmationDialog(
      context,
      title: '预览文件已修改',
      message:
          '是否将对“${p.basename(session.entryPath)}”的修改应用到 ${p.basename(session.archivePath)}？',
      confirmLabel: '应用修改',
      cancelLabel: '暂不应用',
    );
    if (!apply || !mounted) return;

    await _workflow.waitUntilIdle();
    if (!mounted) return;

    try {
      while (true) {
        try {
          await _workflow.updateEntry(
            archivePath: session.archivePath,
            entryPath: session.entryPath,
            sourcePath: session.filePath,
            password: session.password,
          );
          break;
        } on ArchivePasswordRequiredException {
          if (!mounted) return;
          final password = await showPasswordDialog(context, title: '输入压缩包密码');
          if (password == null || !mounted) return;
          session.password = password;
          if (_workflow.listing?.archivePath == session.archivePath) {
            _workflow.rememberPassword(password);
          }
        }
      }
      if (mounted) {
        await showMessageDialog(
          context,
          title: '修改已应用',
          message: '${p.basename(session.entryPath)} 已更新到压缩包。',
        );
      }
    } on ArchiveException catch (error) {
      session.retryPendingChange();
      if (mounted) {
        await showArchiveErrorDialog(context, title: '无法应用修改', error: error);
      }
    }
  }

  List<String> _pathsForEntry(ArchiveListing listing, ArchiveEntry entry) {
    final path = entry.path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    if (!entry.isDirectory) return [path];
    final prefix = '$path/';
    final descendants = listing.entries
        .map((candidate) => candidate.path.replaceAll('\\', '/'))
        .where((candidate) => candidate == path || candidate.startsWith(prefix))
        .toList();
    return descendants.isEmpty ? [path] : descendants;
  }

  List<ArchiveEntry> _topLevelEntries(List<ArchiveEntry> entries) {
    final normalized = entries
        .map(
          (entry) => MapEntry(
            entry.path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), ''),
            entry,
          ),
        )
        .toList();
    final sorted = [...normalized]..sort((a, b) => a.key.compareTo(b.key));
    final selectedPaths = <String>{};
    final parents = <String>{};
    for (final candidate in sorted) {
      var ancestor = p.posix.dirname(candidate.key);
      var covered = false;
      while (ancestor != '.' && ancestor != '/') {
        if (parents.contains(ancestor)) {
          covered = true;
          break;
        }
        ancestor = p.posix.dirname(ancestor);
      }
      if (covered) continue;
      selectedPaths.add(candidate.key);
      if (candidate.value.isDirectory) parents.add(candidate.key);
    }
    final emitted = <String>{};
    return normalized
        .where(
          (entry) =>
              selectedPaths.contains(entry.key) && emitted.add(entry.key),
        )
        .map((entry) => entry.value)
        .toList();
  }
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

class _ArchiveExtractionOutcome {
  const _ArchiveExtractionOutcome._({
    required this.archivePath,
    required this.succeeded,
    this.error,
    this.outputDirectory,
    this.cancelled = false,
  });

  const _ArchiveExtractionOutcome.succeeded(
    String archivePath,
    String directory,
  ) : this._(
        archivePath: archivePath,
        succeeded: true,
        outputDirectory: directory,
      );

  const _ArchiveExtractionOutcome.failed(String archivePath, String error)
    : this._(archivePath: archivePath, succeeded: false, error: error);

  const _ArchiveExtractionOutcome.cancelled(String archivePath)
    : this._(
        archivePath: archivePath,
        succeeded: false,
        error: '操作已取消。',
        cancelled: true,
      );

  final String archivePath;
  final bool succeeded;
  final String? outputDirectory;
  final String? error;
  final bool cancelled;
}

class _ArchiveDragPayload {
  const _ArchiveDragPayload({
    required this.archivePath,
    required this.password,
    required this.entry,
    required this.entryPaths,
  });

  final String archivePath;
  final String? password;
  final ArchiveEntry entry;
  final List<String> entryPaths;
}

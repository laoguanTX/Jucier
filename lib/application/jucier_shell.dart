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
import '../platform/file_preview_service.dart';
import '../platform/single_entry_extraction_preference_store.dart';
import '../screens/archive_screen.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/operation_progress.dart';
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
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.fileLauncher,
    this.singleEntryExtractionMode =
        SingleEntryExtractionMode.preserveArchiveStructure,
    this.onSingleEntryExtractionModeChanged,
    this.archiveColumnPreferences = const ArchiveColumnPreferences(),
    this.onArchiveColumnPreferencesChanged,
    super.key,
  });

  final ArchiveEngine engine;
  final FileAccessService fileAccessService;
  final ArchiveFileAssociationService archiveFileAssociationService;
  final ArchiveOpenService archiveOpenService;
  final FinderActionService finderActionService;
  final bool waitForInitialArchiveOpen;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final FileLauncher? fileLauncher;
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
    _workflow = ArchiveWorkflowController(widget.engine);
    _previews = FilePreviewService(
      launcher: widget.fileLauncher ?? MacOSFileLauncher(),
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
      unawaited(widget.finderActionService.synchronize());
      unawaited(_requestInitialAccess());
    });
  }

  @override
  void dispose() {
    widget.fileAccessService.setOpenSettingsHandler(null);
    widget.archiveOpenService.setHandler(null);
    widget.finderActionService.setHandler(null);
    unawaited(_previews.dispose());
    _archiveDragService.dispose();
    _workflow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _workflow,
    builder: (context, _) => Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _OpenSettingsIntent(),
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
            footer: _workflow.operationLabel == null
                ? null
                : OperationProgress(
                    label: _workflow.operationLabel!,
                    progress: _workflow.progress,
                    onCancel: _workflow.cancel,
                  ),
            child: Padding(
              key: const ValueKey('window-content-padding'),
              padding: EdgeInsets.only(
                top: _isMacOS ? _macOSTrafficLightInset : 0,
              ),
              child: SettingsPageTransition(child: _buildCurrentPage()),
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
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
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
      onDropped: _addDroppedEntries,
      onDragEntries: _dragEntries,
    );
  }

  void _openSettings() {
    if (mounted) setState(() => _settingsOpen = true);
  }

  Future<void> _synchronizeExternalOpenRequests() async {
    await widget.archiveOpenService.synchronize();
    if (mounted) setState(() => _checkingForExternalArchive = false);
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
    setState(() => _draftLoading = true);
    try {
      final listing = await buildArchiveDraftListing(nextSources);
      if (!mounted || !_creatingArchive) return;
      setState(() {
        _draftSources = nextSources;
        _draftListing = listing;
      });
    } on FileSystemException catch (error) {
      if (mounted) {
        await showMessageDialog(context, title: '无法导入', message: error.message);
      }
    } finally {
      if (mounted) setState(() => _draftLoading = false);
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
        await showMessageDialog(context, title: '无法打开', message: error.message);
      }
    }
  }

  Future<void> _openExternalArchive(String path) async {
    if (!isSupportedArchivePath(path)) return;
    await _workflow.waitUntilIdle();
    if (!mounted) return;
    setState(() {
      _openingExternalArchive = true;
      _externalArchiveSession = true;
      _settingsOpen = false;
      _creatingArchive = false;
      _draftLoading = false;
      _draftSources = [];
    });
    await _openArchive(path);
    if (!mounted) return;
    if (_workflow.listing?.archivePath != path) {
      await widget.archiveOpenService.quitApplication();
      return;
    }
    setState(() => _openingExternalArchive = false);
  }

  Future<void> _handleFinderAction(FinderActionRequest request) async {
    await _workflow.waitUntilIdle();
    if (!mounted) return;

    switch (request.type) {
      case FinderActionType.extractHere:
        await _extractFinderArchives(request.paths);
      case FinderActionType.extractTo:
        final archives = request.paths.where(isSupportedArchivePath).toList();
        if (archives.length == 1) await _openExternalArchive(archives.single);
      case FinderActionType.compressZip:
        await _compressFinderSourcesToZip(request.paths);
      case FinderActionType.compress:
        _prepareForFinderWorkflow();
        _startArchiveDraft();
        await _addDraftSources(request.paths);
    }
  }

  void _prepareForFinderWorkflow() {
    _externalArchiveSession = false;
    _settingsOpen = false;
    if (_workflow.listing != null) _workflow.closeArchive();
  }

  Future<void> _extractFinderArchives(List<String> paths) async {
    final archives = paths.where(isSupportedArchivePath).toList();
    _prepareForFinderWorkflow();

    if (archives.isEmpty) {
      await _showFinderExtractionResult(
        title: '解压失败',
        message: '所选项目中没有支持的压缩包。',
      );
      return;
    }

    var completed = 0;
    _FinderExtractionOutcome? stopped;
    for (final archivePath in archives) {
      if (!mounted) return;
      final outcome = await _extractFinderArchive(archivePath);
      if (!outcome.succeeded) {
        stopped = outcome;
        break;
      }
      completed++;
    }

    if (!mounted) return;
    if (stopped != null) {
      final prefix = completed == 0 ? '' : '已成功解压 $completed 个压缩包。\n\n';
      await _showFinderExtractionResult(
        title: '解压失败',
        message: '$prefix${p.basename(stopped.archivePath)}：${stopped.error}',
      );
      return;
    }

    await _showFinderExtractionResult(
      title: '解压完成',
      message: completed == 1
          ? '文件已保存到 ${p.dirname(archives.first)}'
          : '$completed 个压缩包已解压到各自所在位置。',
    );
  }

  Future<void> _showFinderExtractionResult({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showMessageDialog(context, title: title, message: message);
    if (mounted) await widget.archiveOpenService.quitApplication();
  }

  Future<_FinderExtractionOutcome> _extractFinderArchive(
    String archivePath, {
    String? password,
  }) async {
    try {
      await _workflow.extract(
        ExtractArchiveOptions(
          archivePath: archivePath,
          outputDirectory: p.dirname(archivePath),
          password: password,
        ),
      );
      return _FinderExtractionOutcome.succeeded(archivePath);
    } on ArchivePasswordRequiredException {
      if (!mounted) {
        return _FinderExtractionOutcome.failed(archivePath, '应用已关闭。');
      }
      final entered = await showPasswordDialog(
        context,
        title: '输入 ${p.basename(archivePath)} 的密码',
      );
      if (entered == null || !mounted) {
        return _FinderExtractionOutcome.failed(archivePath, '操作已取消。');
      }
      return _extractFinderArchive(archivePath, password: entered);
    } on ArchiveCancelledException {
      return _FinderExtractionOutcome.failed(archivePath, '操作已取消。');
    } on ArchiveException catch (error) {
      return _FinderExtractionOutcome.failed(archivePath, error.message);
    }
  }

  Future<void> _compressFinderSourcesToZip(List<String> paths) async {
    final sources = <String>[];
    for (final path in paths) {
      if (!sources.any((existing) => p.equals(existing, path)) &&
          await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        sources.add(path);
      }
    }
    if (sources.isEmpty || !mounted) return;
    _prepareForFinderWorkflow();
    final archivePath = await _availableZipPath(sources);

    try {
      await _workflow.create(
        CreateArchiveOptions(
          archivePath: archivePath,
          sources: sources,
          format: ArchiveFormat.zip,
        ),
        openAfterCreate: false,
      );
      if (mounted) {
        unawaited(
          showMessageDialog(
            context,
            title: '压缩完成',
            message: '压缩包已保存到 $archivePath',
          ),
        );
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showMessageDialog(context, title: '压缩失败', message: error.message);
      }
    }
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
      await _workflow.create(options);
      if (mounted) {
        setState(() {
          _creatingArchive = false;
          _draftLoading = false;
          _draftSources = [];
        });
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showMessageDialog(context, title: '压缩失败', message: error.message);
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
      await _workflow.extract(options);
      if (mounted) {
        await showMessageDialog(
          context,
          title: '解压完成',
          message: '文件已保存到 ${options.outputDirectory}',
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
        await showMessageDialog(context, title: '解压失败', message: error.message);
      }
    }
  }

  Future<void> _testCurrentArchive() async {
    final listing = _workflow.listing;
    if (listing == null) return;
    try {
      await _workflow.testCurrent();
      if (mounted) {
        await showMessageDialog(context, title: '测试完成', message: '没有发现错误。');
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showMessageDialog(context, title: '测试失败', message: error.message);
      }
    }
  }

  Future<void> _previewEntry(ArchiveEntry entry) async {
    final listing = _workflow.listing;
    if (listing == null || entry.isDirectory || _workflow.busy) return;
    try {
      await _previews.open(
        archivePath: listing.archivePath,
        entryPath: entry.path,
        password: _workflow.password,
        preserveArchiveStructure:
            widget.singleEntryExtractionMode ==
            SingleEntryExtractionMode.preserveArchiveStructure,
        extract: (outputDirectory) => _workflow.extractEntries(
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
    } on ArchivePasswordRequiredException {
      if (mounted) {
        await showMessageDialog(context, title: '无法预览', message: '压缩包密码不正确。');
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showMessageDialog(context, title: '无法预览', message: error.message);
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
      await _workflow.addEntries(
        AddEntriesOptions(
          archivePath: listing.archivePath,
          sources: paths,
          destinationDirectory: directory,
          password: _workflow.password,
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
        await showMessageDialog(context, title: '添加失败', message: error.message);
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
        await showMessageDialog(
          context,
          title: '无法拖出文件',
          message: error.message,
        );
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
    await _workflow.extractEntries(
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
        for (final entry in entries) {
          await _workflow.extractEntries(
            ExtractEntriesOptions(
              archivePath: listing.archivePath,
              entryPaths: _pathsForEntry(listing, entry),
              outputDirectory: outputDirectory,
              password: _workflow.password,
              withoutParentDirectories: true,
              selectedEntryPath: entry.path,
              conflict: entries.length > 1
                  ? ExtractionConflict.rename
                  : ExtractionConflict.overwrite,
            ),
          );
        }
      } else {
        final paths = entries
            .expand((entry) => _pathsForEntry(listing, entry))
            .toSet()
            .toList();
        await _workflow.extractEntries(
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
        await showMessageDialog(context, title: '解压失败', message: error.message);
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
      await _workflow.deleteEntries(paths);
      return true;
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
      return false;
    } on ArchiveException catch (error) {
      if (mounted) {
        await showMessageDialog(context, title: '删除失败', message: error.message);
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
      await _workflow.updateEntry(
        archivePath: session.archivePath,
        entryPath: session.entryPath,
        sourcePath: session.filePath,
        password: session.password,
      );
      if (mounted) {
        await showMessageDialog(
          context,
          title: '修改已应用',
          message: '${p.basename(session.entryPath)} 已更新到压缩包。',
        );
      }
    } on ArchiveException catch (error) {
      if (mounted) {
        await showMessageDialog(
          context,
          title: '无法应用修改',
          message: error.message,
        );
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
    return normalized
        .where(
          (candidate) => !normalized.any(
            (other) =>
                other.key != candidate.key &&
                other.value.isDirectory &&
                candidate.key.startsWith('${other.key}/'),
          ),
        )
        .map((entry) => entry.value)
        .toList();
  }
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

class _FinderExtractionOutcome {
  const _FinderExtractionOutcome._({
    required this.archivePath,
    required this.succeeded,
    this.error,
  });

  const _FinderExtractionOutcome.succeeded(String archivePath)
    : this._(archivePath: archivePath, succeeded: true);

  const _FinderExtractionOutcome.failed(String archivePath, String error)
    : this._(archivePath: archivePath, succeeded: false, error: error);

  final String archivePath;
  final bool succeeded;
  final String? error;
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

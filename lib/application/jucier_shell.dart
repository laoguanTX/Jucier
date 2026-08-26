import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

import '../archive/archive_engine.dart';
import '../archive/archive_formats.dart';
import '../dialogs/create_archive_dialog.dart';
import '../dialogs/extract_dialog.dart';
import '../dialogs/message_dialog.dart';
import '../dialogs/password_dialog.dart';
import '../platform/file_access_service.dart';
import '../screens/archive_screen.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/operation_progress.dart';
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
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    super.key,
  });

  final ArchiveEngine engine;
  final FileAccessService fileAccessService;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<JucierShell> createState() => _JucierShellState();
}

class _JucierShellState extends State<JucierShell> {
  late final ArchiveWorkflowController _workflow;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    _workflow = ArchiveWorkflowController(widget.engine);
    widget.fileAccessService.setOpenSettingsHandler(_openSettings);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _requestInitialAccess(),
    );
  }

  @override
  void dispose() {
    widget.fileAccessService.setOpenSettingsHandler(null);
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
    if (_settingsOpen) {
      return SettingsScreen(
        key: const ValueKey('settings-page'),
        fileAccessService: widget.fileAccessService,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onBack: () => setState(() => _settingsOpen = false),
      );
    }
    if (_workflow.listing == null) {
      return HomeScreen(
        key: const ValueKey('home-page'),
        enabled: !_workflow.busy,
        onOpen: _pickArchive,
        onCreate: _pickSources,
        onSettings: _openSettings,
        onDropped: _handleDroppedPaths,
      );
    }
    return ArchiveScreen(
      key: const ValueKey('archive-page'),
      listing: _workflow.listing!,
      enabled: !_workflow.busy,
      onClose: _workflow.closeArchive,
      onExtract: _extractCurrentArchive,
      onTest: _testCurrentArchive,
    );
  }

  void _openSettings() {
    if (mounted) setState(() => _settingsOpen = true);
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

  Future<void> _pickSources() async {
    final choice = await showSourcePicker(context);
    if (!mounted || choice == null) return;

    final List<String> paths;
    if (choice == SourcePickerChoice.files) {
      paths = (await openFiles(confirmButtonText: '选择'))
          .map((file) => file.path)
          .toList();
    } else {
      final path = await getDirectoryPath(confirmButtonText: '选择文件夹');
      paths = [?path];
    }
    if (paths.isNotEmpty && mounted) await _showCreateDialog(paths);
  }

  Future<void> _handleDroppedPaths(List<String> paths) async {
    if (_workflow.busy || paths.isEmpty) return;
    if (paths.length == 1 && isSupportedArchivePath(paths.single)) {
      await _openArchive(paths.single);
    } else {
      await _showCreateDialog(paths);
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

  Future<void> _showCreateDialog(List<String> paths) async {
    final options = await showCreateArchiveDialog(context, sources: paths);
    if (options == null || !mounted) return;

    try {
      await _workflow.create(options);
      if (mounted) {
        await showMessageDialog(
          context,
          title: '压缩完成',
          message: '已创建 ${options.archivePath}',
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
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'archive/archive_engine.dart';
import 'archive/archive_entry.dart';
import 'archive/seven_zip_engine.dart';
import 'dialogs/create_archive_dialog.dart';
import 'dialogs/extract_dialog.dart';
import 'dialogs/message_dialog.dart';
import 'dialogs/password_dialog.dart';
import 'platform/file_access_service.dart';
import 'screens/archive_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/operation_progress.dart';

class JucierApp extends StatelessWidget {
  const JucierApp({super.key, this.engine, this.fileAccessService});

  final ArchiveEngine? engine;
  final FileAccessService? fileAccessService;

  @override
  Widget build(BuildContext context) {
    final light = FTheme.neutral.light.desktop;
    final dark = FTheme.neutral.dark.desktop;

    return MaterialApp(
      title: 'jucier',
      debugShowCheckedModeBanner: false,
      theme: light.toApproximateMaterialTheme(),
      darkTheme: dark.toApproximateMaterialTheme(),
      themeMode: ThemeMode.system,
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: const [...FLocalizations.localizationsDelegates],
      builder: (context, child) {
        final data = MediaQuery.platformBrightnessOf(context) == Brightness.dark
            ? dark
            : light;
        return FTheme(
          data: data,
          child: FToaster(
            child: FTooltipGroup(
              // A handful of compact desktop controls in the archive forms
              // come from material_ui. FScaffold and FDialog intentionally do
              // not insert a Material ancestor, so provide one at the app
              // boundary for every route and overlay.
              child: Material(type: MaterialType.transparency, child: child!),
            ),
          ),
        );
      },
      home: JucierShell(
        engine: engine ?? SevenZipEngine(),
        fileAccessService: fileAccessService ?? MacOSFileAccessService(),
      ),
    );
  }
}

class JucierShell extends StatefulWidget {
  const JucierShell({
    required this.engine,
    required this.fileAccessService,
    super.key,
  });

  final ArchiveEngine engine;
  final FileAccessService fileAccessService;

  @override
  State<JucierShell> createState() => _JucierShellState();
}

class _JucierShellState extends State<JucierShell> {
  ArchiveListing? _listing;
  String? _password;
  String? _operationLabel;
  double? _progress;
  bool _settingsOpen = false;

  bool get _busy => _operationLabel != null;

  @override
  void initState() {
    super.initState();
    widget.fileAccessService.setOpenSettingsHandler(_openSettings);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _requestInitialAccess(),
    );
  }

  @override
  void dispose() {
    widget.fileAccessService.setOpenSettingsHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
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
          footer: _operationLabel == null
              ? null
              : OperationProgress(
                  label: _operationLabel!,
                  progress: _progress,
                  onCancel: widget.engine.cancel,
                ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 460),
            reverseDuration: const Duration(milliseconds: 340),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) =>
                _buildPageTransition(context, child, animation),
            child: _buildCurrentPage(),
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
        onBack: () => setState(() => _settingsOpen = false),
      );
    }
    if (_listing == null) {
      return HomeScreen(
        key: const ValueKey('home-page'),
        enabled: !_busy,
        onOpen: _pickArchive,
        onCreate: _pickSources,
        onSettings: _openSettings,
        onDropped: _handleDroppedPaths,
      );
    }
    return ArchiveScreen(
      key: const ValueKey('archive-page'),
      listing: _listing!,
      enabled: !_busy,
      onClose: () => setState(() {
        _listing = null;
        _password = null;
      }),
      onExtract: _extractCurrentArchive,
      onTest: _testCurrentArchive,
    );
  }

  Widget _buildPageTransition(
    BuildContext context,
    Widget child,
    Animation<double> animation,
  ) {
    if (child.key != const ValueKey('settings-page')) {
      return FadeTransition(opacity: animation, child: child);
    }

    return AnimatedBuilder(
      key: const ValueKey('settings-circular-reveal'),
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(animation.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipPath(clipper: _CircularRevealClipper(progress), child: child),
            IgnorePointer(
              child: CustomPaint(
                painter: _CircularRipplePainter(
                  progress,
                  context.theme.colors.primary,
                ),
              ),
            ),
          ],
        );
      },
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
      extensions: <String>[
        '7z',
        'zip',
        'rar',
        'tar',
        'gz',
        'bz2',
        'xz',
        'zst',
        'cab',
        'iso',
        'dmg',
      ],
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
    if (_busy || paths.isEmpty) return;
    if (paths.length == 1 && _looksLikeArchive(paths.single)) {
      await _openArchive(paths.single);
    } else {
      await _showCreateDialog(paths);
    }
  }

  bool _looksLikeArchive(String path) {
    const extensions = {
      '.7z',
      '.zip',
      '.rar',
      '.tar',
      '.gz',
      '.bz2',
      '.xz',
      '.zst',
      '.cab',
      '.iso',
      '.dmg',
    };
    return extensions.contains(p.extension(path).toLowerCase());
  }

  Future<void> _openArchive(String path, {String? password}) async {
    _beginOperation('正在打开 ${p.basename(path)}');
    try {
      final listing = await widget.engine.list(path, password: password);
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _password = password;
      });
    } on ArchivePasswordRequiredException {
      if (!mounted) return;
      final entered = await showPasswordDialog(context, title: '输入压缩包密码');
      if (entered != null && mounted) {
        _endOperation();
        await _openArchive(path, password: entered);
        return;
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showMessageDialog(context, title: '无法打开', message: error.message);
      }
    } finally {
      if (mounted) _endOperation();
    }
  }

  Future<void> _showCreateDialog(List<String> paths) async {
    final options = await showCreateArchiveDialog(context, sources: paths);
    if (options == null || !mounted) return;

    _beginOperation('正在创建 ${p.basename(options.archivePath)}', progress: 0);
    try {
      await widget.engine.create(options, onProgress: _updateProgress);
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
    } finally {
      if (mounted) _endOperation();
    }
  }

  Future<void> _extractCurrentArchive() async {
    final listing = _listing;
    if (listing == null) return;
    final options = await showExtractDialog(
      context,
      archivePath: listing.archivePath,
      initialPassword: _password,
    );
    if (options == null || !mounted) return;

    _beginOperation('正在解压 ${p.basename(listing.archivePath)}', progress: 0);
    try {
      await widget.engine.extract(options, onProgress: _updateProgress);
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
    } finally {
      if (mounted) _endOperation();
    }
  }

  Future<void> _testCurrentArchive() async {
    final listing = _listing;
    if (listing == null) return;
    _beginOperation('正在测试 ${p.basename(listing.archivePath)}', progress: 0);
    try {
      await widget.engine.test(
        listing.archivePath,
        password: _password,
        onProgress: _updateProgress,
      );
      if (mounted) {
        await showMessageDialog(context, title: '测试完成', message: '没有发现错误。');
      }
    } on ArchiveCancelledException {
      // Explicit cancellations do not need an error dialog.
    } on ArchiveException catch (error) {
      if (mounted) {
        await showMessageDialog(context, title: '测试失败', message: error.message);
      }
    } finally {
      if (mounted) _endOperation();
    }
  }

  void _updateProgress(double value) {
    if (mounted) setState(() => _progress = value);
  }

  void _beginOperation(String label, {double? progress}) {
    setState(() {
      _operationLabel = label;
      _progress = progress;
    });
  }

  void _endOperation() {
    setState(() {
      _operationLabel = null;
      _progress = null;
    });
  }
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

Offset _settingsRevealOrigin(Size size) => Offset(size.width - 52, 42);

double _settingsRevealRadius(Size size) {
  final origin = _settingsRevealOrigin(size);
  return math.sqrt(
    origin.dx * origin.dx +
        (size.height - origin.dy) * (size.height - origin.dy),
  );
}

class _CircularRevealClipper extends CustomClipper<Path> {
  const _CircularRevealClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) => Path()
    ..addOval(
      Rect.fromCircle(
        center: _settingsRevealOrigin(size),
        radius: _settingsRevealRadius(size) * progress,
      ),
    );

  @override
  bool shouldReclip(_CircularRevealClipper oldClipper) =>
      progress != oldClipper.progress;
}

class _CircularRipplePainter extends CustomPainter {
  const _CircularRipplePainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    canvas.drawCircle(
      _settingsRevealOrigin(size),
      _settingsRevealRadius(size) * progress,
      Paint()
        ..color = color.withValues(alpha: (1 - progress) * 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_CircularRipplePainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}

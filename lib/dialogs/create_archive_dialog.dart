import 'package:file_selector/file_selector.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_options.dart';

enum SourcePickerChoice { files, folder }

Future<SourcePickerChoice?> showSourcePicker(BuildContext context) =>
    showFDialog<SourcePickerChoice>(
      context: context,
      builder: (context, _, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(minWidth: 390, maxWidth: 430),
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('创建压缩包', style: style.titleTextStyle),
              const SizedBox(height: 8),
              Text('选择要添加的内容', style: style.bodyTextStyle),
              const SizedBox(height: 20),
              FButton(
                onPress: () =>
                    Navigator.of(context).pop(SourcePickerChoice.files),
                prefix: const Icon(FLucideIcons.files, size: 17),
                child: const Text('选择文件'),
              ),
              const SizedBox(height: 8),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () =>
                    Navigator.of(context).pop(SourcePickerChoice.folder),
                prefix: const Icon(FLucideIcons.folder, size: 17),
                child: const Text('选择文件夹'),
              ),
            ],
          ),
        ),
      ),
    );

Future<CreateArchiveOptions?> showCreateArchiveDialog(
  BuildContext context, {
  required List<String> sources,
}) => showFDialog<CreateArchiveOptions>(
  context: context,
  barrierDismissible: false,
  builder: (context, _, animation) => FDialog(
    animation: animation,
    constraints: const BoxConstraints(minWidth: 500, maxWidth: 560),
    builder: (context, style) =>
        _CreateArchiveForm(style: style, sources: sources),
  ),
);

class _CreateArchiveForm extends StatefulWidget {
  const _CreateArchiveForm({required this.style, required this.sources});

  final FDialogStyle style;
  final List<String> sources;

  @override
  State<_CreateArchiveForm> createState() => _CreateArchiveFormState();
}

class _CreateArchiveFormState extends State<_CreateArchiveForm> {
  late final TextEditingController _pathController;
  final _passwordController = TextEditingController();
  final _volumeController = TextEditingController();
  ArchiveFormat _format = ArchiveFormat.sevenZip;
  double _level = 5;
  String? _error;

  @override
  void initState() {
    super.initState();
    final first = widget.sources.first;
    final base = widget.sources.length == 1
        ? p.basenameWithoutExtension(first)
        : 'Archive';
    _pathController = TextEditingController(
      text: p.join(p.dirname(first), '$base.7z'),
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    _passwordController.dispose();
    _volumeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('创建压缩包', style: widget.style.titleTextStyle),
          const SizedBox(height: 6),
          Text(
            '${widget.sources.length} 个来源',
            style: widget.style.bodyTextStyle,
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    labelText: '保存位置',
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FButton(
                size: FButtonSizeVariant.sm,
                variant: FButtonVariant.outline,
                onPress: _chooseLocation,
                child: const Text('选择'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ArchiveFormat>(
                  initialValue: _format,
                  decoration: const InputDecoration(labelText: '格式'),
                  items: [
                    for (final format in ArchiveFormat.values)
                      DropdownMenuItem(
                        value: format,
                        child: Text(format.label),
                      ),
                  ],
                  onChanged: _changeFormat,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('压缩等级 ${_level.round()}'),
                    Slider(
                      value: _level,
                      min: 0,
                      max: 9,
                      divisions: 9,
                      onChanged: (value) => setState(() => _level = value),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            enabled:
                _format == ArchiveFormat.sevenZip ||
                _format == ArchiveFormat.zip,
            obscureText: true,
            decoration: InputDecoration(
              labelText:
                  _format == ArchiveFormat.sevenZip ||
                      _format == ArchiveFormat.zip
                  ? '密码（可选）'
                  : '${_format.label} 不支持密码',
            ),
          ),
          const SizedBox(height: 8),
          FAccordion(
            children: [
              FAccordionItem(
                title: const Text('高级选项'),
                child: TextField(
                  controller: _volumeController,
                  decoration: const InputDecoration(labelText: '分卷大小'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FButton(
                size: FButtonSizeVariant.sm,
                variant: FButtonVariant.ghost,
                onPress: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FButton(
                size: FButtonSizeVariant.sm,
                onPress: _submit,
                child: const Text('创建'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _chooseLocation() async {
    final location = await getSaveLocation(
      suggestedName: p.basename(_pathController.text),
      initialDirectory: p.dirname(_pathController.text),
      acceptedTypeGroups: [
        XTypeGroup(label: _format.label, extensions: [_format.extension]),
      ],
      confirmButtonText: '保存',
    );
    if (location != null) setState(() => _pathController.text = location.path);
  }

  void _changeFormat(ArchiveFormat? format) {
    if (format == null) return;
    setState(() {
      final withoutExtension = p.withoutExtension(_pathController.text);
      _format = format;
      if (format != ArchiveFormat.sevenZip && format != ArchiveFormat.zip) {
        _passwordController.clear();
      }
      _pathController.text = '$withoutExtension.${format.extension}';
    });
  }

  void _submit() {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _error = '请选择保存位置');
      return;
    }
    if (_format == ArchiveFormat.gzip && widget.sources.length != 1) {
      setState(() => _error = 'GZIP 一次只能压缩一个文件');
      return;
    }
    Navigator.of(context).pop(
      CreateArchiveOptions(
        archivePath: path,
        sources: widget.sources,
        format: _format,
        compressionLevel: _level.round(),
        password: _passwordController.text.trim().isEmpty
            ? null
            : _passwordController.text,
        volumeSize: _volumeController.text.trim().isEmpty
            ? null
            : _volumeController.text.trim(),
      ),
    );
  }
}

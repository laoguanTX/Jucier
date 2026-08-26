import 'package:file_selector/file_selector.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_options.dart';

typedef ExtractDirectoryPicker = Future<String?> Function({
  required String initialDirectory,
});

Future<ExtractArchiveOptions?> showExtractDialog(
  BuildContext context, {
  required String archivePath,
  String? initialPassword,
  ExtractDirectoryPicker? directoryPicker,
}) => showFDialog<ExtractArchiveOptions>(
  context: context,
  barrierDismissible: false,
  builder: (context, _, animation) => FDialog(
    animation: animation,
    constraints: const BoxConstraints(minWidth: 500, maxWidth: 560),
    builder: (context, style) => _ExtractForm(
      style: style,
      archivePath: archivePath,
      initialPassword: initialPassword,
      directoryPicker: directoryPicker ?? _pickExtractDirectory,
    ),
  ),
);

Future<String?> _pickExtractDirectory({required String initialDirectory}) =>
    getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: '选择',
      canCreateDirectories: true,
    );

class _ExtractForm extends StatefulWidget {
  const _ExtractForm({
    required this.style,
    required this.archivePath,
    required this.directoryPicker,
    this.initialPassword,
  });

  final FDialogStyle style;
  final String archivePath;
  final String? initialPassword;
  final ExtractDirectoryPicker directoryPicker;

  @override
  State<_ExtractForm> createState() => _ExtractFormState();
}

class _ExtractFormState extends State<_ExtractForm> {
  late final TextEditingController _directoryController;
  late final TextEditingController _passwordController;
  ExtractionConflict _conflict = ExtractionConflict.overwrite;

  @override
  void initState() {
    super.initState();
    _directoryController = TextEditingController();
    _passwordController = TextEditingController(
      text: widget.initialPassword ?? '',
    );
  }

  @override
  void dispose() {
    _directoryController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('解压文件', style: widget.style.titleTextStyle),
        const SizedBox(height: 6),
        Text(p.basename(widget.archivePath), style: widget.style.bodyTextStyle),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _directoryController,
                readOnly: true,
                onTap: _chooseDirectory,
                decoration: InputDecoration(
                  labelText: '解压到',
                  hintText: '请选择或新建一个文件夹',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FButton(
              size: FButtonSizeVariant.sm,
              variant: FButtonVariant.outline,
              onPress: _chooseDirectory,
              child: const Text('选择'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<ExtractionConflict>(
          initialValue: _conflict,
          decoration: const InputDecoration(labelText: '文件冲突'),
          items: [
            for (final option in ExtractionConflict.values)
              DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _conflict = value);
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: '密码（可选）'),
        ),
        const SizedBox(height: 22),
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
              child: const Text('解压'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _chooseDirectory() async {
    final path = await widget.directoryPicker(
      initialDirectory: _directoryController.text.isEmpty
          ? p.dirname(widget.archivePath)
          : _directoryController.text,
    );
    if (path != null && mounted) {
      setState(() => _directoryController.text = path);
    }
  }

  Future<void> _submit() async {
    if (_directoryController.text.isEmpty) {
      await _chooseDirectory();
      if (!mounted || _directoryController.text.isEmpty) return;
    }

    final directory = _directoryController.text.trim();
    Navigator.of(context).pop(
      ExtractArchiveOptions(
        archivePath: widget.archivePath,
        outputDirectory: directory,
        conflict: _conflict,
        password: _passwordController.text.isEmpty
            ? null
            : _passwordController.text,
      ),
    );
  }
}

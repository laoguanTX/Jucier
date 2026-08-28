import 'package:file_selector/file_selector.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_options.dart';

enum SourcePickerChoice { files, folder }

enum _VolumeUnit {
  kilobytes('KB', 'k'),
  megabytes('MB', 'm'),
  gigabytes('GB', 'g');

  const _VolumeUnit(this.label, this.sevenZipSuffix);

  final String label;
  final String sevenZipSuffix;
}

Future<SourcePickerChoice?> showSourcePicker(
  BuildContext context, {
  String title = '创建压缩包',
  String description = '选择要添加的内容',
}) => showFDialog<SourcePickerChoice>(
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
          Text(title, style: style.titleTextStyle),
          const SizedBox(height: 8),
          Text(description, style: style.bodyTextStyle),
          const SizedBox(height: 20),
          FButton(
            onPress: () => Navigator.of(context).pop(SourcePickerChoice.files),
            prefix: const Icon(FLucideIcons.files, size: 17),
            child: const Text('选择文件'),
          ),
          const SizedBox(height: 8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.of(context).pop(SourcePickerChoice.folder),
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
  builder: (context, _, animation) {
    final availableHeight = MediaQuery.sizeOf(context).height - 48;
    return FDialog(
      animation: animation,
      constraints: BoxConstraints(
        minWidth: 500,
        maxWidth: 560,
        maxHeight: availableHeight,
      ),
      builder: (context, style) => SingleChildScrollView(
        child: _CreateArchiveForm(style: style, sources: sources),
      ),
    );
  },
);

class _CreateArchiveForm extends StatefulWidget {
  const _CreateArchiveForm({required this.style, required this.sources});

  final FDialogStyle style;
  final List<String> sources;

  @override
  State<_CreateArchiveForm> createState() => _CreateArchiveFormState();
}

class _CreateArchiveFormState extends State<_CreateArchiveForm> {
  static const double _formatWidth = 150;
  static const double _controlHeight = 48;
  static const double _sectionRowHeight = 72;

  late final TextEditingController _pathController;
  final _passwordController = TextEditingController();
  final _volumeController = TextEditingController();
  ArchiveFormat _format = ArchiveFormat.zip;
  _VolumeUnit _volumeUnit = _VolumeUnit.megabytes;
  bool _advancedExpanded = false;
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
      text: p.join(p.dirname(first), '$base.${_format.extension}'),
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
    final smallTitleStyle = context.theme.typography.body.sm.copyWith(
      color: context.theme.colors.foreground,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.none,
    );
    final largeTitleStyle = context.theme.typography.display.xl.copyWith(
      color: context.theme.colors.foreground,
      fontWeight: FontWeight.w600,
    );
    final mediumTitleStyle = context.theme.typography.display.lg.copyWith(
      color: context.theme.colors.foreground,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.none,
    );

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '创建压缩包',
            key: const ValueKey('create-archive-title'),
            style: largeTitleStyle,
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.sources.length} 个来源',
            style: widget.style.bodyTextStyle,
          ),
          const SizedBox(height: 12),
          Text(
            '保存位置',
            key: const ValueKey('save-location-title'),
            style: smallTitleStyle,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: _controlHeight,
                  child: FTextField(
                    key: const ValueKey('save-location-field'),
                    control: FTextFieldControl.managed(
                      controller: _pathController,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: _controlHeight,
                child: FButton(
                  key: const ValueKey('save-location-button'),
                  size: FButtonSizeVariant.md,
                  variant: FButtonVariant.outline,
                  onPress: _chooseLocation,
                  child: const Text('  选择  '),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 5),
            Text(
              _error!,
              key: const ValueKey('save-location-error'),
              style: context.theme.typography.body.xs.copyWith(
                color: context.theme.colors.error,
              ),
            ),
          ],
          // const SizedBox(height: 14),
          SizedBox(
            key: const ValueKey('compression-controls-row'),
            height: _sectionRowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _formatWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '压缩格式',
                        key: const ValueKey('archive-format-title'),
                        style: smallTitleStyle,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: _controlHeight,
                        child: _buildFormatSelect(),
                      ),
                    ],
                  ),
                ),
                // const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '压缩等级 ${_level.round()}',
                        key: const ValueKey('compression-level-title'),
                        style: smallTitleStyle,
                      ),
                      SizedBox(
                        height: _controlHeight,
                        child: Slider(
                          value: _level,
                          min: 0,
                          max: 9,
                          divisions: 9,
                          onChanged: (value) => setState(() => _level = value),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // const SizedBox(height: 8),
          Text(
            '压缩密码',
            key: const ValueKey('compression-password-title'),
            style: smallTitleStyle,
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: _controlHeight,
            child: FTextField(
              key: const ValueKey('compression-password-field'),
              control: FTextFieldControl.managed(
                controller: _passwordController,
              ),
              enabled: _format.supportsPassword,
              obscureText: true,
              hint: '可选',
            ),
          ),
          FAccordion(
            control: FAccordionControl.lifted(
              expanded: (index) => index == 0 && _advancedExpanded,
              onChange: (index, expanded) {
                if (index == 0) setState(() => _advancedExpanded = expanded);
              },
            ),
            children: [
              FAccordionItem(
                title: Text(
                  '高级选项',
                  key: const ValueKey('advanced-options-title'),
                  style: mediumTitleStyle,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分卷大小',
                      key: const ValueKey('volume-size-title'),
                      style: smallTitleStyle,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: _controlHeight,
                            child: FTextField(
                              key: const ValueKey('volume-size-field'),
                              control: FTextFieldControl.managed(
                                controller: _volumeController,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 96,
                          height: _controlHeight,
                          child: _buildVolumeUnitSelect(),
                        ),
                      ],
                    ),
                  ],
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

  Widget _buildFormatSelect() => FSelect<ArchiveFormat>.rich(
    key: const ValueKey('archive-format-select'),
    control: FSelectControl.lifted(value: _format, onChange: _changeFormat),
    format: (format) => ' .${format.extension}',
    contentConstraints: const FAutoWidthPortalConstraints(maxHeight: 344),
    children: [
      for (final format in ArchiveFormat.values)
        FSelectItem<ArchiveFormat>(
          key: ValueKey('archive-format-${format.extension}'),
          value: format,
          title: Text(format.label),
        ),
    ],
  );

  Widget _buildVolumeUnitSelect() => FSelect<_VolumeUnit>(
    key: const ValueKey('volume-unit-select'),
    control: FSelectControl.lifted(
      value: _volumeUnit,
      onChange: (unit) {
        if (unit != null) setState(() => _volumeUnit = unit);
      },
    ),
    items: {for (final unit in _VolumeUnit.values) unit.label: unit},
    contentConstraints: const FAutoWidthPortalConstraints(maxHeight: 160),
  );

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
      if (!format.supportsPassword) {
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
    if (_format.singleSourceOnly && widget.sources.length != 1) {
      setState(() => _error = '${_format.label} 一次只能压缩一个文件');
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
            : '${_volumeController.text.trim()}${_volumeUnit.sevenZipSuffix}',
      ),
    );
  }
}

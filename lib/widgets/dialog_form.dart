import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

const dialogControlHeight = 48.0;
const _dialogTextFieldStyle = FTextFieldStyleDelta.delta(
  constraints: BoxConstraints(
    minHeight: dialogControlHeight,
    maxHeight: dialogControlHeight,
  ),
);

final dialogSelectStyle = FSelectStyleDelta.delta(
  fieldStyles: FVariantsDelta.delta([
    FVariantOperation.all(_dialogTextFieldStyle),
  ]),
);

/// Labels live above controls so they do not change the control's height.
class DialogFormLabel extends StatelessWidget {
  const DialogFormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.theme.typography.body.sm.copyWith(
      color: context.theme.colors.foreground,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.none,
    ),
  );
}

/// The shared single-line input for desktop dialogs.
class DialogTextField extends StatelessWidget {
  const DialogTextField({
    super.key,
    required this.controller,
    this.hint,
    this.readOnly = false,
    this.enabled = true,
    this.obscureText = false,
    this.autofocus = false,
    this.keyboardType,
    this.onTap,
    this.onSubmit,
  });

  final TextEditingController controller;
  final String? hint;
  final bool readOnly;
  final bool enabled;
  final bool obscureText;
  final bool autofocus;
  final TextInputType? keyboardType;
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmit;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: dialogControlHeight,
    child: FTextField(
      style: _dialogTextFieldStyle,
      control: FTextFieldControl.managed(controller: controller),
      textAlignVertical: TextAlignVertical.center,
      hint: hint,
      readOnly: readOnly,
      enabled: enabled,
      obscureText: obscureText,
      autofocus: autofocus,
      keyboardType: keyboardType,
      onTap: onTap,
      onSubmit: onSubmit,
    ),
  );
}

/// One layout for both archive save paths and extraction directories.
class PathPickerField extends StatelessWidget {
  const PathPickerField({
    super.key,
    required this.controller,
    required this.onPick,
    this.hint,
    this.readOnly = false,
    this.fieldKey,
    this.buttonKey,
  });

  final TextEditingController controller;
  final VoidCallback onPick;
  final String? hint;
  final bool readOnly;
  final Key? fieldKey;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: DialogTextField(
          key: fieldKey,
          controller: controller,
          hint: hint,
          readOnly: readOnly,
          onTap: readOnly ? onPick : null,
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        height: dialogControlHeight,
        width: 88,
        child: FButton(
          key: buttonKey,
          size: FButtonSizeVariant.md,
          variant: FButtonVariant.outline,
          onPress: onPick,
          child: const Text('选择'),
        ),
      ),
    ],
  );
}

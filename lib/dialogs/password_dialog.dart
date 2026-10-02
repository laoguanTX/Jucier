import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/dialog_form.dart';

Future<String?> showPasswordDialog(
  BuildContext context, {
  required String title,
}) => showFDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (context, _, animation) => FDialog(
    animation: animation,
    constraints: const BoxConstraints(minWidth: 400, maxWidth: 460),
    builder: (context, style) => _PasswordForm(title: title, style: style),
  ),
);

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({required this.title, required this.style});

  final String title;
  final FDialogStyle style;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isNotEmpty) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: widget.style.titleTextStyle),
        const SizedBox(height: 16),
        const DialogFormLabel('密码'),
        const SizedBox(height: 6),
        DialogTextField(
          key: const ValueKey('password-dialog-field'),
          controller: _controller,
          autofocus: true,
          obscureText: true,
          onSubmit: (_) => _submit(),
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
              child: const Text('继续'),
            ),
          ],
        ),
      ],
    ),
  );
}

import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Callback type for HITL confirmation result
typedef ConfirmCallback = void Function(bool approved);

/// Shows a confirmation dialog for MCP tool execution
/// Returns true if user approves, false if denied
Future<bool> showToolConfirmationDialog({
  required BuildContext context,
  required String toolName,
  required Map<String, dynamic> arguments,
}) async {
  final loc = AppLocalizations.of(context)!;
  final result = await showMacosAlertDialog<bool>(
    context: context,
    builder: (_) => MacosAlertDialog(
      appIcon: const Icon(CupertinoIcons.bolt_fill, size: 48, color: CupertinoColors.systemYellow),
      title: Text(loc.toolConfirmTitle),
      message: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(loc.toolConfirmBody),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.toolConfirmToolLabel(toolName), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(loc.toolConfirmArgsLabel(_formatArgs(arguments, loc)), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, true),
        child: Text(loc.toolConfirmAllow),
      ),
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context, false),
        child: Text(loc.toolConfirmDeny),
      ),
    ),
  );
  
  return result ?? false;
}

String _formatArgs(Map<String, dynamic> args, AppLocalizations loc) {
  if (args.isEmpty) return loc.toolConfirmNoArgs;
  return args.entries.map((e) => '${e.key}: ${e.value}').join(', ');
}

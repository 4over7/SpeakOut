import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

/// Callback type for HITL confirmation result
typedef ConfirmCallback = void Function(bool approved);

/// Shows a confirmation dialog for MCP tool execution
/// Returns true if user approves, false if denied
Future<bool> showToolConfirmationDialog({
  required BuildContext context,
  required String toolName,
  required Map<String, dynamic> arguments,
}) async {
  final result = await showMacosAlertDialog<bool>(
    context: context,
    builder: (_) => MacosAlertDialog(
      appIcon: const Icon(CupertinoIcons.bolt_fill, size: 48, color: CupertinoColors.systemYellow),
      title: const Text('执行 Agent 命令?'),
      message: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('SpeakOut 想要执行以下操作：'),
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
                Text('工具: $toolName', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('参数: ${_formatArgs(arguments)}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, true),
        child: const Text('允许'),
      ),
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context, false),
        child: const Text('拒绝'),
      ),
    ),
  );
  
  return result ?? false;
}

String _formatArgs(Map<String, dynamic> args) {
  if (args.isEmpty) return '(无)';
  return args.entries.map((e) => '${e.key}: ${e.value}').join(', ');
}

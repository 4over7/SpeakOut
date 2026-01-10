import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:uuid/uuid.dart';
import '../../services/mcp_config_service.dart';
import '../../ui/theme.dart';

class AddServerDialog extends StatefulWidget {
  const AddServerDialog({super.key});

  @override
  State<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<AddServerDialog> {
  final TextEditingController _labelCtrl = TextEditingController();
  final TextEditingController _cmdCtrl = TextEditingController();
  final TextEditingController _argsCtrl = TextEditingController(); // Space separated for now
  
  // TODO: More advanced ENV and CWD editing
  
  @override
  Widget build(BuildContext context) {
    return MacosSheet(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text("Add MCP Server", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            Expanded(
              child: Column(
                children: [
                   _buildTextField(
                     controller: _labelCtrl,
                     placeholder: "Display Name (e.g. Calendar)",
                   ),
                   const SizedBox(height: 12),
                   _buildTextField(
                     controller: _cmdCtrl,
                     placeholder: "Command (e.g. python3)",
                   ),
                   const SizedBox(height: 12),
                   _buildTextField(
                     controller: _argsCtrl,
                     placeholder: "Arguments (e.g. /path/to/script.py)",
                   ),
                   const SizedBox(height: 8),
                   Text("Separate arguments with spaces", style: AppTheme.caption(context)),
                ],
              ),
            ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                 PushButton(
                   controlSize: ControlSize.large,
                   secondary: true,
                   onPressed: () => Navigator.pop(context),
                   child: const Text("Cancel"),
                 ),
                 const SizedBox(width: 12),
                 PushButton(
                   controlSize: ControlSize.large,
                   onPressed: _submit,
                   child: const Text("Add"),
                 ),
              ],
            )
          ],
        ),
      ),
    );
  }
  
  Widget _buildTextField({
    required TextEditingController controller,
    required String placeholder,
  }) {
    return MacosTextField(
      controller: controller,
      placeholder: placeholder,
      maxLines: 1,
      style: AppTheme.body(context),
      placeholderStyle: const TextStyle(color: MacosColors.systemGrayColor),
      decoration: BoxDecoration(
        color: AppTheme.getInputBackground(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.getBorder(context)),
      ),
      focusedDecoration: BoxDecoration(
        color: AppTheme.getInputBackground(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.getAccent(context), width: 2),
      ),
    );
  }

  void _submit() {
    if (_labelCtrl.text.isEmpty || _cmdCtrl.text.isEmpty) {
       // Valid
       return;
    }
    
    // Naive args parsing
    final args = _argsCtrl.text.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    
    final config = McpServerConfig(
      id: const Uuid().v4(),
      label: _labelCtrl.text,
      command: _cmdCtrl.text,
      args: args,
      cwd: null, // Default
      env: null,
    );
    
    Navigator.pop(context, config);
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../services/mcp_config_service.dart';
import '../../services/agent_service.dart';
import '../../services/mcp_client.dart';
import '../../ui/theme.dart';
import 'add_server_dialog.dart';

class McpSettingsView extends StatefulWidget {
  const McpSettingsView({super.key});

  @override
  State<McpSettingsView> createState() => _McpSettingsViewState();
}

class _McpSettingsViewState extends State<McpSettingsView> {
  @override
  void initState() {
    super.initState();
    McpConfigService().addListener(_onConfigChanged);
    AgentService().statusStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    McpConfigService().removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final servers = McpConfigService().servers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Agent Tools (MCP)", style: AppTheme.heading(context)),
            PushButton(
              controlSize: ControlSize.regular,
              onPressed: () => _showAddServerDialog(context),
              child: const Text("Add Server"),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "Connect external tools to SpeakOut. The AI will dynamically discover and use them.",
          style: AppTheme.caption(context),
        ),
        const SizedBox(height: 16),

        // Server List
        if (servers.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.getInputBackground(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.getBorder(context)),
            ),
            child: Column(
              children: [
                const Icon(CupertinoIcons.cube_box, size: 48, color: MacosColors.systemGrayColor),
                const SizedBox(height: 16),
                const Text("No tools configured."),
                const SizedBox(height: 8),
                Text("Use 'Add Server' to connect an MCP service.", style: AppTheme.caption(context)),
              ],
            ),
          )
        else
          ...servers.map((server) => _buildServerCard(server)),
      ],
    );
  }

  Widget _buildServerCard(McpServerConfig server) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getInputBackground(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.getBorder(context)),
      ),
      child: Row(
        children: [
          // Icon Status
          _buildStatusDot(context, server),
          const SizedBox(width: 12),
          
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(server.label, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  "${server.command} ${server.args.join(' ')}", 
                  style: AppTheme.mono(context).copyWith(fontSize: 10),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Actions
          if (AgentService().serverStatuses[server.id] == McpConnectionStatus.error ||
              AgentService().serverStatuses[server.id] == McpConnectionStatus.disconnected)
            MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.refresh, size: 16),
              onPressed: () => AgentService().retryServer(server.id),
            ),
          
          MacosSwitch(
            value: server.enabled,
            onChanged: (v) {
               // Initial version: toggle disabled state only locally or actually stop client?
               // For config only now.
               final newConf = McpServerConfig(
                 id: server.id, label: server.label, command: server.command, 
                 args: server.args, cwd: server.cwd, env: server.env, 
                 enabled: v
               );
               McpConfigService().updateServer(newConf);
            },
          ),
          const SizedBox(width: 8),
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.trash, size: 16),
            onPressed: () => _confirmDelete(server),
          ),
        ],
      ),
    );
  }

  void _showAddServerDialog(BuildContext context) async {
    final result = await showMacosSheet(
      context: context,
      builder: (_) => const AddServerDialog(),
    );
    
    if (result is McpServerConfig) {
      await McpConfigService().addServer(result);
    }
  }

  void _confirmDelete(McpServerConfig server) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const Icon(CupertinoIcons.delete),
        title: const Text('Remove Server?'),
        message: Text('Are you sure you want to remove ${server.label}?'),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () {
            McpConfigService().removeServer(server.id);
            Navigator.pop(context);
          },
          child: const Text('Remove'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
  Widget _buildStatusDot(BuildContext context, McpServerConfig server) {
    if (!server.enabled) {
      return _buildIcon(CupertinoIcons.cube_box, MacosColors.systemGrayColor);
    }
    
    final status = AgentService().serverStatuses[server.id] ?? McpConnectionStatus.disconnected;
    Color color;
    IconData icon;
    
    switch (status) {
      case McpConnectionStatus.connected:
        color = MacosColors.systemGreenColor;
        icon = CupertinoIcons.cube_box_fill;
        break;
      case McpConnectionStatus.connecting:
        color = MacosColors.systemYellowColor;
        icon = CupertinoIcons.arrow_2_circlepath;
        break;
      case McpConnectionStatus.error:
        color = MacosColors.systemRedColor;
        icon = CupertinoIcons.exclamationmark_triangle_fill;
        break;
      case McpConnectionStatus.disconnected:
        color = MacosColors.systemRedColor;
        icon = CupertinoIcons.bolt_slash_fill;
        break;
    }
    
    return _buildIcon(icon, color);
  }

  Widget _buildIcon(IconData icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: color),
    );
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class McpServerConfig {
  final String id;
  final String label;
  final String command;
  final List<String> args;
  final String? cwd;
  final Map<String, String>? env;
  final bool enabled;

  McpServerConfig({
    required this.id,
    required this.label,
    required this.command,
    this.args = const [],
    this.cwd,
    this.env,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'command': command,
    'args': args,
    'cwd': cwd,
    'env': env,
    'enabled': enabled,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      id: json['id'] ?? const Uuid().v4(),
      label: json['label'] ?? 'Unknown Server',
      command: json['command'] ?? '',
      args: List<String>.from(json['args'] ?? []),
      cwd: json['cwd'],
      env: json['env'] != null ? Map<String, String>.from(json['env']) : null,
      enabled: json['enabled'] ?? true,
    );
  }
}

class McpConfigService extends ChangeNotifier {
  static final McpConfigService _instance = McpConfigService._internal();
  factory McpConfigService() => _instance;
  McpConfigService._internal();

  late SharedPreferences _prefs;
  bool _initialized = false;
  
  List<McpServerConfig> _servers = [];
  List<McpServerConfig> get servers => List.unmodifiable(_servers);

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    
    final jsonStr = _prefs.getString('mcp_servers_config');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        _servers = list.map((e) => McpServerConfig.fromJson(e)).toList();
      } catch (e) {
        debugPrint("[McpConfigService] Load failed: $e");
        _servers = [];
      }
    }
    
    _initialized = true;
    notifyListeners();
  }

  Future<void> save() async {
    final jsonStr = jsonEncode(_servers.map((e) => e.toJson()).toList());
    await _prefs.setString('mcp_servers_config', jsonStr);
    notifyListeners();
  }

  Future<void> addServer(McpServerConfig config) async {
    _servers.add(config);
    await save();
  }

  Future<void> removeServer(String id) async {
    _servers.removeWhere((s) => s.id == id);
    await save();
  }

  Future<void> updateServer(McpServerConfig newConfig) async {
    final index = _servers.indexWhere((s) => s.id == newConfig.id);
    if (index >= 0) {
      _servers[index] = newConfig;
      await save();
    }
  }
}

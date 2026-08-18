
enum ChatRole {
  user,     // Typed by user
  ai,       // AI Reply (Chat)
  system,   // System Info / Voice Note log
  tool,     // Agent Tool Execution Result
  dictation // Input Mode (Text Injection) History
}

class ChatMessage {
  final String id;
  final String text;
  final ChatRole role;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata; // e.g. Tool Name, "SavedToDiary": true

  ChatMessage({
    required this.id,
    required this.text,
    required this.role,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'role': role.name,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      text: json['text'] as String,
      role: _roleFromJson(json['role']),
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  static ChatRole _roleFromJson(Object? value) {
    if (value is int) {
      return value >= 0 && value < ChatRole.values.length
          ? ChatRole.values[value]
          : ChatRole.system;
    }
    if (value is String) {
      for (final role in ChatRole.values) {
        if (role.name == value) return role;
      }
      return ChatRole.system;
    }
    throw const FormatException('ChatMessage.role 格式无效');
  }
}

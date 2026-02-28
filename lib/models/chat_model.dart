
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
      role: json['role'] is int
          ? ChatRole.values[json['role'] as int]
          : ChatRole.values.firstWhere((r) => r.name == json['role'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

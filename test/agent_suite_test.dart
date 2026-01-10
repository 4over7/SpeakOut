import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/models/chat_model.dart';
import 'package:speakout/services/agent_service.dart';
import 'package:speakout/services/mcp_client.dart';

// Mock AgentService parts? 
// AgentService is singleton, hard to reset. We test components around it.

void main() {
  group('Chat System Tests', () {
    test('ChatMessage Serialization', () {
      final msg = ChatMessage(
        id: '123',
        text: 'Hello',
        role: ChatRole.user,
        timestamp: DateTime.utc(2025, 1, 1),
        metadata: {'tool': 'calendar'}
      );
      
      final json = msg.toJson();
      expect(json['id'], '123');
      expect(json['role'], ChatRole.user.index);
      expect(json['metadata']['tool'], 'calendar');
      
      final reconstructed = ChatMessage.fromJson(json);
      expect(reconstructed.id, msg.id);
      expect(reconstructed.timestamp, msg.timestamp);
    });
  });

  group('Agent Security (HITL)', () {
    test('PendingToolCall Approval Flow', () async {
      final call = PendingToolCall(
        id: '1', 
        toolName: 'test_tool', 
        arguments: {}
      );
      
      // Simulate User Approval
      Future.delayed(const Duration(milliseconds: 10), () => call.approve());
      
      final result = await call.completer.future;
      expect(result, true);
    });
    
    test('PendingToolCall Denial Flow', () async {
      final call = PendingToolCall(
        id: '2', 
        toolName: 'rm -rf', 
        arguments: {}
      );
      
      call.deny();
      
      final result = await call.completer.future;
      expect(result, false);
    });
  });
  
  group('MCP Robustness Logic', () {
    test('Retry Backoff Calculation', () {
      // Simulate the logic in AgentService._scheduleReconnect
      int calculateDelay(int retries) => (retries + 1) * 2;
      
      expect(calculateDelay(0), 2); // 1st retry: 2s
      expect(calculateDelay(1), 4); // 2nd retry: 4s
      expect(calculateDelay(4), 10); // 5th retry: 10s
    });
    
    test('Status Enum Integrity', () {
      expect(McpConnectionStatus.values.length, 4);
      expect(McpConnectionStatus.disconnected.index, 0);
    });
  });
}

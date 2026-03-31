import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

/// Design System for SpeakOut v4.0 — 墨竹 (Emerald Bamboo)
/// Deep emerald accent with warm recording orange, dual-mode (dark/light).
class AppTheme {
  // === PRIMARY COLORS — 墨竹翡翠绿 ===

  // Dark mode accent
  static const Color darkAccent = Color(0xFF00B074);
  // Light mode accent
  static const Color lightAccent = Color(0xFF009660);

  // Legacy alias — resolves to mode-appropriate accent at runtime
  static const Color accentColor = Color(0xFF00B074);

  static Color getAccent(BuildContext context) {
    return MacosTheme.brightnessOf(context) == Brightness.dark
        ? darkAccent
        : lightAccent;
  }

  // === RECORDING COLORS ===
  static const Color darkRecording = Color(0xFFFF8C42);
  static const Color lightRecording = Color(0xFFE06830);

  static Color getRecordingColor(BuildContext context) {
    return MacosTheme.brightnessOf(context) == Brightness.dark
        ? darkRecording
        : lightRecording;
  }

  // === BACKGROUNDS — 墨竹配色 ===

  // Dark Mode
  static const Color darkBackground = Color(0xFF141414);
  static const Color darkCardBackground = Color(0xFF1E1E1E);
  static const Color darkBorder = Color(0xFF2A2A2A);

  // Light Mode
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightCardBackground = Color(0xFFFFFFFF);
  static const Color lightSidebarBackground = Color(0xFFF0F0F0);
  static const Color lightBorder = Color(0xFFE8E8E8);

  // === TEXT COLORS ===
  static const Color darkTextPrimary = Color(0xFFEBEBEB);
  static const Color darkTextSecondary = Color(0xFF777777);
  static const Color lightTextPrimary = Color(0xFF1A1A1A);
  static const Color lightTextSecondary = Color(0xFF999999);

  static Color getTextPrimary(BuildContext context) {
    return MacosTheme.brightnessOf(context) == Brightness.dark
        ? darkTextPrimary
        : lightTextPrimary;
  }

  static Color getTextSecondary(BuildContext context) {
    return MacosTheme.brightnessOf(context) == Brightness.dark
        ? darkTextSecondary
        : lightTextSecondary;
  }

  // === SEMANTIC COLORS ===
  static const Color errorColor = CupertinoColors.systemRed;
  static const Color successColor = CupertinoColors.systemGreen;

  // === TRIGGER CARD ACCENT COLORS ===
  static const Color triggerVoice = Color(0xFF00B074);   // 语音 — 绿
  static const Color triggerNote = Color(0xFF9B59B6);     // 笔记 — 紫
  static const Color triggerOrganize = Color(0xFF1ABC9C); // 梳理 — 青
  static const Color triggerTranslate = Color(0xFF3498DB);// 翻译 — 蓝
  static const Color triggerCorrect = Color(0xFFE67E22);  // 纠错 — 橙
  static const Color triggerAiReport = Color(0xFFE74C3C); // AI报告 — 红

  // === DYNAMIC GETTERS ===

  static Color getBackground(BuildContext context) {
    return MacosTheme.brightnessOf(context) == Brightness.dark
        ? darkBackground
        : lightBackground;
  }

  static Color getCardBackground(BuildContext context) {
    return MacosTheme.brightnessOf(context) == Brightness.dark
        ? darkCardBackground
        : lightCardBackground;
  }

  static Color getSidebarBackground(BuildContext context) {
    return MacosTheme.brightnessOf(context) == Brightness.dark
        ? darkCardBackground
        : lightSidebarBackground;
  }

  static Color getBorder(BuildContext context) {
    return MacosTheme.brightnessOf(context) == Brightness.dark
        ? darkBorder
        : lightBorder;
  }

  static Color getInputBackground(BuildContext context) {
    return MacosTheme.brightnessOf(context) == Brightness.dark
        ? const Color(0xFF2A2A2A)
        : lightCardBackground;
  }

  // === TYPOGRAPHY ===

  static TextStyle display(BuildContext context) {
    return TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: getTextPrimary(context),
    );
  }

  static TextStyle heading(BuildContext context) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: getTextSecondary(context),
    );
  }

  static TextStyle body(BuildContext context) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.normal,
      color: getTextPrimary(context),
    );
  }

  static TextStyle caption(BuildContext context) {
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: getTextSecondary(context),
    );
  }

  static TextStyle mono(BuildContext context) {
    return TextStyle(
      fontFamily: 'Menlo',
      fontSize: 12,
      color: getTextPrimary(context),
    );
  }
}

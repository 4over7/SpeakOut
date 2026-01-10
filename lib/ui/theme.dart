import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

/// Design System for SpeakOut v3.4.0
/// Flat design with Mint Green accent - simple and approachable.
class AppTheme {
  // === PRIMARY COLORS ===
  
  // Mint Green - friendly and fresh (same for both modes)
  static const Color accentColor = Color(0xFF2ECC71); // Mint Green
  
  static Color getAccent(BuildContext context) {
    return accentColor; // Same color for both modes
  }
  
  // === BACKGROUNDS (Standard macOS) ===
  
  // Dark Mode
  static const Color darkBackground = Color(0xFF1C1C1E);
  static const Color darkCardBackground = Color(0xFF2C2C2E);
  static const Color darkBorder = Color(0xFF3C3C3E);
  
  // Light Mode
  static const Color lightBackground = Color(0xFFF5F5F7);
  static const Color lightCardBackground = Color(0xFFFFFFFF);
  static const Color lightSidebarBackground = Color(0xFFF0F0F0);
  static const Color lightBorder = Color(0xFFE5E5E5);
  
  // === SEMANTIC COLORS ===
  static const Color errorColor = CupertinoColors.systemRed;
  static const Color successColor = CupertinoColors.systemGreen;
  
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
        ? const Color(0xFF38383A) // Lighter than card for contrast
        : lightCardBackground;
  }
  
  // === TYPOGRAPHY ===
  
  static TextStyle display(BuildContext context) {
    return TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: MacosTheme.of(context).typography.headline.color,
    );
  }

  static TextStyle heading(BuildContext context) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: MacosColors.secondaryLabelColor.resolveFrom(context),
    );
  }
  
  static TextStyle body(BuildContext context) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.normal,
      color: MacosTheme.of(context).typography.body.color,
    );
  }

  static TextStyle caption(BuildContext context) {
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: MacosColors.secondaryLabelColor.resolveFrom(context),
    );
  }
  
  static TextStyle mono(BuildContext context) {
    return TextStyle(
      fontFamily: 'Menlo',
      fontSize: 12,
      color: MacosTheme.of(context).typography.body.color,
    );
  }
}

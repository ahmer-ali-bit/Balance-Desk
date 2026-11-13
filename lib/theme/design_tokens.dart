import 'package:flutter/material.dart';

/// Premium design tokens for the Balance Desk redesign.
class DesignTokens {
  DesignTokens._();

  // ── Canvas & Surfaces ────────────────────────────────────────────────
  static const Color canvas = Color(0xFF07090D);
  static const Color canvasDeep = Color(0xFF05070B);
  static const Color surface = Color(0xFF0D1117);
  static const Color surfaceRaised = Color(0xFF131A23);
  static const Color surfaceElevated = Color(0xFF182130);
  static const Color surfaceOverlay = Color(0xFF1D2836);
  static const Color surfaceInput = Color(0xFF0A0F16);

  // ── Primary & Secondary ──────────────────────────────────────────────
  static const Color primary = Color(0xFF10B981);
  static const Color primaryDeep = Color(0xFF065F46);
  static const Color primarySoft = Color(0xFF34D399);
  static const Color onPrimary = Color(0xFF03261D);
  static const Color primaryContainer = Color(0xFF0E3B31);
  static const Color onPrimaryContainer = Color(0xFFA7F3D0);

  static const Color secondary = Color(0xFFD4A44E);
  static const Color secondaryDeep = Color(0xFF92610F);
  static const Color onSecondary = Color(0xFF2A1A04);
  static const Color secondaryContainer = Color(0xFF3B2A10);
  static const Color onSecondaryContainer = Color(0xFFF5DEB3);

  // ── Semantic Signals ──────────────────────────────────────────────────
  static const Color debit = Color(0xFF10B981);
  static const Color debitSoft = Color(0xFF6EE7B7);
  static const Color debitDeep = Color(0xFF0B5E4B);
  static const Color credit = Color(0xFFF43F5E);
  static const Color creditSoft = Color(0xFFFDA4AF);
  static const Color creditDeep = Color(0xFF8C1D33);
  static const Color neutral = Color(0xFF94A3B8);

  // ── Typography helpers ───────────────────────────────────────────────
  static const double eyebrowLetterSpacing = 1.8;
  static const double eyebrowFontSize = 10.0;

  static TextStyle headingLarge(Color color, ThemeData theme) {
    return theme.textTheme.headlineLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ) ??
        TextStyle(color: color, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -0.8);
  }

  static TextStyle headingMedium(Color color, ThemeData theme) {
    return theme.textTheme.headlineMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ) ??
        TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.6);
  }

  static TextStyle headingSmall(Color color, ThemeData theme) {
    return theme.textTheme.titleLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ) ??
        TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4);
  }

  static TextStyle bodyLarge(Color color, ThemeData theme) {
    return theme.textTheme.bodyLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ) ??
        TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w500, height: 1.45);
  }

  static TextStyle bodySmall(Color color, ThemeData theme) {
    return theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ) ??
        TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4);
  }

  static TextStyle labelLarge(Color color, ThemeData theme) {
    return theme.textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ) ??
        TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.4);
  }

  static TextStyle labelMedium(Color color, ThemeData theme) {
    return theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ) ??
        TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2);
  }

  static TextStyle labelSmall(Color color, ThemeData theme) {
    return theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          fontSize: 11,
        ) ??
        TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8);
  }
}
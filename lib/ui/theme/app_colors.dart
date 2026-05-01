import 'package:flutter/material.dart';

/// Traxio Driver Benchmarking System — Mandatory Color System.
///
/// Transportation-grade professional palette.
/// Do NOT change these values.
class AppColors {
  AppColors._();

  // ─── Primary ─────────────────────────────────────────────────────
  static const Color primary = Color(0xFF1E3A8A);
  static const Color primaryLight = Color(0xFF3B5CB8);
  static const Color primaryDark = Color(0xFF152C6B);

  // ─── Light Mode ──────────────────────────────────────────────────
  static const Color lightBackground = Color(0xFFF4F6F9);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);

  // ─── Dark Mode ───────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkSurface = Color(0xFF1E293B);

  // ─── Text ────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnDark = Color(0xFFF1F5F9);
  static const Color textOnDarkSecondary = Color(0xFF94A3B8);

  // ─── Terrain (Strict) ────────────────────────────────────────────
  static const Color terrainPlain = Color(0xFF16A34A);
  static const Color terrainUphill = Color(0xFFEA580C);
  static const Color terrainDownhill = Color(0xFF2563EB);

  // ─── Terrain Backgrounds (20% opacity) ───────────────────────────
  static const Color terrainPlainBg = Color(0x3316A34A);
  static const Color terrainUphillBg = Color(0x33EA580C);
  static const Color terrainDownhillBg = Color(0x332563EB);

  // ─── Alert / Status ──────────────────────────────────────────────
  static const Color alert = Color(0xFFDC2626);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);

  // ─── Divider / Border ────────────────────────────────────────────
  static const Color dividerLight = Color(0xFFE2E8F0);
  static const Color dividerDark = Color(0xFF334155);

  /// Get terrain color by terrain name string.
  static Color terrainColor(String terrain) {
    switch (terrain) {
      case 'Plain':
        return terrainPlain;
      case 'Uphill':
        return terrainUphill;
      case 'Downhill':
        return terrainDownhill;
      default:
        return textMuted;
    }
  }

  /// Get terrain background color by terrain name.
  static Color terrainBgColor(String terrain) {
    switch (terrain) {
      case 'Plain':
        return terrainPlainBg;
      case 'Uphill':
        return terrainUphillBg;
      case 'Downhill':
        return terrainDownhillBg;
      default:
        return const Color(0x1494A3B8);
    }
  }
}

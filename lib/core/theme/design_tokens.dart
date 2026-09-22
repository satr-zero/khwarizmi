import 'package:flutter/material.dart';

/// Central Design Tokens for Khwarizmi AI Agent.
/// Strict monochrome visual identity, adhering to Section 2 of the specification.
abstract final class DesignTokens {
  // ── Light Palette ────────────────────────────────────────────────────────
  static const Color bgLight = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF7F7F7);
  static const Color surfaceInputLight = Color(0xFFF0F0F0);
  static const Color textPrimaryLight = Color(0xFF0A0A0A);
  static const Color textSecondaryLight = Color(0xFF6B6B6B);
  static const Color borderLight = Color(0xFFE5E5E5);
  static const Color hoverLight = Color(0xFFECECEC);

  // ── Dark Palette ─────────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF0A0A0A);
  static const Color surfaceDark = Color(0xFF151515);
  static const Color surfaceInputDark = Color(0xFF1C1C1C);
  static const Color textPrimaryDark = Color(0xFFF2F2F2);
  static const Color textSecondaryDark = Color(0xFF909090);
  static const Color borderDark = Color(0xFF2A2A2A);
  static const Color hoverDark = Color(0xFF222222);

  // ── Functional Status (Monochrome — shape & weight based, no garish colors) ─
  // Light Mode Status Tokens
  static const Color statusSuccessLight = Color(0xFF333333);
  static const Color statusErrorLight = Color(0xFF0A0A0A);
  static const Color statusPendingLight = Color(0xFF666666);
  static const Color statusBadgeBgLight = Color(0xFFEBEBEB);

  // Dark Mode Status Tokens
  static const Color statusSuccessDark = Color(0xFFCCCCCC);
  static const Color statusErrorDark = Color(0xFFF2F2F2);
  static const Color statusPendingDark = Color(0xFF888888);
  static const Color statusBadgeBgDark = Color(0xFF222222);

  // ── Typography Scale (5 defined proportional steps) ──────────────────────
  static const double fontSizeXs = 11.0;     // Micro labels, badges, timestamps
  static const double fontSizeSm = 13.0;     // Secondary text, params, compact buttons
  static const double fontSizeBase = 15.0;   // Primary body text, chat dialogue
  static const double fontSizeLg = 18.0;     // Subtitles, section headings
  static const double fontSizeXl = 24.0;     // Dialog headers, brand title
  static const double fontSize2Xl = 32.0;    // Hero welcome title

  // ── Font Families ────────────────────────────────────────────────────────
  static const String fontFamilySans = 'Geist';
  static const String fontFamilyArabic = 'IBMPlexSansArabic';
  static const String fontFamilyMono = 'GeistMono';

  static const List<String> sansFallbacks = [
    'IBMPlexSansArabic',
    'Segoe UI',
    '-apple-system',
    'sans-serif',
  ];

  static const List<String> monoFallbacks = [
    'Consolas',
    'Cascadia Code',
    'Courier New',
    'monospace',
  ];

  // ── Spacing Scale ────────────────────────────────────────────────────────
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;

  // ── Border Radii (Clean, non-cliché geometry) ─────────────────────────────
  static const double radiusSm = 4.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;

  // ── Border Widths ────────────────────────────────────────────────────────
  static const double hairline = 1.0;
  static const double hairlineThick = 1.5;

  // ── Layout Breakpoints ───────────────────────────────────────────────────
  /// عرض النافذة أقل من هذا → وضع مضغوط: شريط مطوي، لوحات overlay
  static const double breakpointCompact = 900.0;
  /// عرض النافذة أكبر من هذا → وضع عريض: ثلاثة أعمدة مسموحة
  static const double breakpointWide = 1400.0;

  // ── Sidebar ──────────────────────────────────────────────────────────────
  /// عرض الشريط الجانبي الكامل (وضع standard/wide)
  static const double sidebarWidthFull = 280.0;
  /// عرض الشريط المطوي — أيقونات فقط مع tooltips
  static const double sidebarWidthCollapsed = 56.0;

  // ── Content ──────────────────────────────────────────────────────────────
  /// الحد الأقصى لعرض عمود المحادثة — يمنع سطوراً طويلة جداً
  static const double chatMaxWidth = 750.0;
  /// ارتفاع الشريط العلوي — ثابت لكل الأحجام
  static const double topBarHeight = 48.0;

  // ── Work Panel (Browser / Terminal) ─────────────────────────────────────
  static const double workPanelMinWidth = 320.0;
  static const double workPanelDefaultWidth = 480.0;
  static const double workPanelMaxWidth = 700.0;

  // ── Collapsed Message ────────────────────────────────────────────────────
  /// الارتفاع الأقصى لرد مساعد قبل إضافة "عرض المزيد"
  static const double messageMaxCollapsedHeight = 480.0;
}


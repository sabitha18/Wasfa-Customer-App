import 'package:flutter/material.dart';

/// Design tokens — mirrors the `:root{ --token: value }` block in
/// WASFA_App_-_PHASE_1.html exactly. This file is the single source of
/// truth for color; never hardcode a hex value in a screen/widget.
class AppColors {
  AppColors._();

  static const navy = Color(0xFF023B60); // primary / Trust Navy
  static const sky = Color(0xFF1E9CD7); // secondary / Smart Sky
  static const rose = Color(0xFFE7609F); // accent / offers / Medic Rose
  static const aqua = Color(0xFF58C4E4); // tertiary / care / Digital Aqua
  static const cloud = Color(0xFFE6EBF0); // lines / dividers
  static const blush = Color(0xFFFFF7F9); // soft rose tint
  static const ink = Color(0xFF0E2433); // text primary
  static const muted = Color(0xFF6B7C8A); // text secondary
  static const line = Color(0xFFE6EBF0);
  static const bg = Color(0xFFF4F7FA); // app background
  static const white = Color(0xFFFFFFFF);

  static const ok = Color(0xFF22B07D);
  static const warn = Color(0xFFE89B2B);
  static const danger = Color(0xFFE5484D);
  static const star = Color(0xFFE89B2B);

  // PDP-specific pale tints (.srow.on background, .benef .b background,
  // .srow .sp2 .best background) — named here rather than inlined in
  // product_screen.dart per the "AppColors is the source of truth" rule.
  static const skySelectedBg = Color(0xFFF2FAFE); // .srow.on
  static const benefitPillBg = Color(0xFFEAF4FB); // .benef .b
  static const bestPriceBg = Color(0xFFE4F6EF); // .srow .sp2 .best

  // Store detail page (.store-top / .freedel)
  static const storeTopGradient = [Color(0xFFFCE6D6), Colors.white];
  static const freeDeliveryOrange = Color(0xFFE0622A);

  // Promo carousel gradients (p1 / p2 / p3 in the HTML)
  static const promo1 = [Color(0xFF023B60), Color(0xFF1E9CD7)];
  static const promo2 = [Color(0xFF1E9CD7), Color(0xFF58C4E4)];
  static const promo3 = [Color(0xFFE7609F), Color(0xFFA83A72)];

  // Elevation (shadows) — sh-sm / sh / sh-lg
  static List<BoxShadow> shSm = [
    BoxShadow(color: navy.withOpacity(.06), blurRadius: 12, offset: const Offset(0, 3)),
  ];
  static List<BoxShadow> sh = [
    BoxShadow(color: navy.withOpacity(.10), blurRadius: 26, offset: const Offset(0, 8)),
  ];
  static List<BoxShadow> shLg = [
    BoxShadow(color: navy.withOpacity(.16), blurRadius: 40, offset: const Offset(0, 16)),
  ];
}

/// Radius tokens — r-card / r-ctl / r-pill / r-sheet
class AppRadius {
  AppRadius._();
  static const card = 16.0;
  static const ctl = 11.0;
  static const pill = 24.0;
  static const sheet = 22.0;
}

/// Spacing scale — s1..s6
class AppSpacing {
  AppSpacing._();
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
}

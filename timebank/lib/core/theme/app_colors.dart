import 'package:flutter/material.dart';

/// The palette.
///
/// Designed as an instrument panel rather than a social app: a near-black
/// canvas, a narrow range of greys that carry the structure, and exactly
/// one accent colour reserved for the thing that matters — credits.
///
/// The canvas is #08080A rather than pure #000000. A fraction of blue
/// stops large dark areas reading as a dead pixel field, and it gives the
/// greys above it something to sit against.
///
/// Credits are brass, not green. Green would read as "success" on every
/// balance, including a negative one. Brass reads as currency, which is
/// what a credit is, and leaves green and red free to mean up and down.
abstract final class AppColors {
  // Surfaces, darkest to lightest.
  static const canvas       = Color(0xFF08080A);
  static const surface      = Color(0xFF101014);
  static const surfaceRaised= Color(0xFF17171D);
  static const surfaceHover = Color(0xFF1E1E26);

  // Hairlines. Borders do the structural work here instead of shadows,
  // which are close to invisible on a black background anyway.
  static const border       = Color(0xFF26262F);
  static const borderStrong = Color(0xFF35353F);

  // Type.
  static const textPrimary  = Color(0xFFEDEDF2);
  static const textSecondary= Color(0xFF9B9BA8);
  static const textMuted    = Color(0xFF5E5E6B);

  // The one accent: credits, primary actions, the selected tab.
  static const accent       = Color(0xFFD9A441);
  static const accentDim    = Color(0xFF8A6A2A);
  static const accentWash   = Color(0x1AD9A441);   // 10% for fills

  // Semantics. Used only on values and status chips, never as decoration.
  static const positive     = Color(0xFF4FB477);
  static const negative     = Color(0xFFE0564E);
  static const info         = Color(0xFF6E8FD6);

  /// Status chip colour for a booking.
  static Color forStatus(String status) => switch (status.toUpperCase()) {
        'COMPLETED' => positive,
        'CONFIRMED' => info,
        'REQUESTED' => accent,
        'DISPUTED'  => negative,
        'CANCELLED' => textMuted,
        _           => textSecondary,
      };

  /// Green for credits in, red for credits out, muted for zero.
  static Color forAmount(num amount) => amount > 0
      ? positive
      : amount < 0
          ? negative
          : textMuted;
}

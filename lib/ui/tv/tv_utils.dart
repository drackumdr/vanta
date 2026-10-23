import 'package:flutter/material.dart';

/// Utilidades de diseño e interacción para Android TV y pantallas grandes.
class TvUtils {
  /// Margen de seguridad para televisores contra sobreexploración (overscan).
  static const EdgeInsets overscanPadding = EdgeInsets.symmetric(
    horizontal: 28,
    vertical: 16,
  );

  /// Color de foco característico para control remoto.
  static const Color focusColor = Color(0xFF00E5FF);

  /// Color de acento secundario para selección TV.
  static const Color accentColor = Color(0xFF2979FF);

  /// Evalúa si el contexto actual se beneficia de comodidades de TV (pantallas apaisadas 16:9 grandes).
  static bool isTvScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width >= 960 && (size.width / size.height) >= 1.4;
  }
}

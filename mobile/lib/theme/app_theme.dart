import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta y tipografía de Cupón App.
/// Concepto: "ticket de caza" — papel color hueso + tinta de sello teal
/// + rojo-coral de sello de goma para las acciones principales.
class AppColors {
  static const ivoryPaper = Color(0xFFFBF1DE);
  static const inkTeal = Color(0xFF0E4F4A);
  static const inkTealDark = Color(0xFF08302D);
  static const stampCoral = Color(0xFFE8543B);
  static const goldFoil = Color(0xFFD9A441);
  static const textInk = Color(0xFF1C2521);
  static const mutedInk = Color(0xFF8B8578);
}

class AppTheme {
  static TextTheme get _textTheme {
    return TextTheme(
      displayLarge: GoogleFonts.anton(
        fontSize: 40,
        color: Colors.black,
        letterSpacing: 1.2,
        height: 1.05,
      ),
      displayMedium: GoogleFonts.anton(
        fontSize: 28,
        color: Colors.black,
        letterSpacing: 1.0,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: Colors.black,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 16,
        color: Colors.black,
        height: 1.4,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 14,
        color: Colors.black,
        height: 1.4,
      ),
      labelLarge: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: Colors.black,
      ),
    );
  }

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

    // Se combinan los estilos por defecto de Material con los de la app
    // y se fuerza el color negro en TODOS (título de diálogos, ítems de
    // menús desplegables, listas, etc.).
    final textTheme = base.textTheme
        .merge(_textTheme)
        .apply(bodyColor: Colors.black, displayColor: Colors.black);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.ivoryPaper,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.inkTeal,
        secondary: AppColors.stampCoral,
        surface: AppColors.ivoryPaper,
        onSurface: Colors.black,
        tertiary: AppColors.goldFoil,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.ivoryPaper,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        titleTextStyle: GoogleFonts.anton(
          fontSize: 20,
          color: Colors.black,
          letterSpacing: 1.0,
        ),
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.black,
        ),
        contentTextStyle: GoogleFonts.manrope(
          fontSize: 14,
          color: Colors.black,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: GoogleFonts.manrope(color: Colors.black),
      ),
      popupMenuTheme: PopupMenuThemeData(
        textStyle: GoogleFonts.manrope(color: Colors.black),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Colors.black,
        iconColor: Colors.black,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.black),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.goldFoil,
        contentTextStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.stampCoral,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(52),
          textStyle: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.stampCoral,
          foregroundColor: Colors.black,
          textStyle: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.inkTeal,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.inkTeal, width: 1.6),
          textStyle: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.mutedInk.withOpacity(0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.mutedInk.withOpacity(0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inkTeal, width: 1.8),
        ),
        // Textos de los campos en negro.
        labelStyle: GoogleFonts.manrope(color: Colors.black),
        floatingLabelStyle: GoogleFonts.manrope(color: Colors.black),
        hintStyle: GoogleFonts.manrope(color: Colors.black54),
        helperStyle: GoogleFonts.manrope(color: Colors.black87),
        prefixStyle: GoogleFonts.manrope(color: Colors.black),
        suffixStyle: GoogleFonts.manrope(color: Colors.black),
      ),
    );
  }
}
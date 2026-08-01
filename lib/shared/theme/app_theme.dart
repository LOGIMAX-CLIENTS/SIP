import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Palette
  static const Color midnightNavy   = Color(0xFF020817);
  // arcticBlue is now the PRIMARY GREEN — used as the brand accent everywhere
  static const Color arcticBlue     = Color(0xFF1B882C);
  static const Color electricCyan   = Color(0xFF1B882C);  // mapped to same green
  static const Color glassWhite     = Color(0xFFF8FAFC);
  static const Color auroraPurple   = Color(0xFF8B5CF6);
  static const Color primaryGreen   = Color(0xFF1B882C);
  static const Color darkGreen      = Color(0xFF003716);
  static const Color buttonShadow   = Color(0x3B8F4C05);

  /// Standard green gradient — same as Login / OTP button
  static const LinearGradient greenGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF1B882C), Color(0xFF003716)],
  );

  // ── Global App Background Gradients ─────────────────────────────────────
  static const LinearGradient lightGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFDF5), Color(0xFFFFE6A8)],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF020617), Color(0xFF0F172A)],
  );
  // ─────────────────────────────────────────────────────────────────────────

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.playfairDisplay().fontFamily,
      brightness: Brightness.light,
      primaryColor: primaryGreen,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        brightness: Brightness.light,
        primary: primaryGreen,
        secondary: electricCyan,
        surface: glassWhite,
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w700),
        displayMedium: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w700),
        displaySmall: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w700),
        headlineLarge: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w600),
        headlineSmall: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w400),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: midnightNavy),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, 64.h),
          textStyle: TextStyle(
            fontFamily: GoogleFonts.playfairDisplay().fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
          elevation: 4,
          shadowColor: buttonShadow,
        ),
      ),
    );
  }



  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.playfairDisplay().fontFamily,
      brightness: Brightness.dark,
      primaryColor: primaryGreen,
      scaffoldBackgroundColor: midnightNavy,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        brightness: Brightness.dark,
        surface: const Color(0xFF0F172A),
        primary: primaryGreen,
        secondary: auroraPurple,
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w700, color: Colors.white),
        displayMedium: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w700, color: Colors.white),
        displaySmall: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w700, color: Colors.white),
        headlineLarge: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w700, color: Colors.white),
        headlineMedium: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w600, color: Colors.white),
        headlineSmall: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w600, color: Colors.white),
        titleLarge: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w600, color: Colors.white),
        titleMedium: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w500, color: Colors.white),
        titleSmall: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w500, color: Colors.white),
        bodyLarge: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w400, color: Colors.white70),
        bodyMedium: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w400, color: Colors.white70),
        bodySmall: TextStyle(fontFamily: GoogleFonts.playfairDisplay().fontFamily, fontWeight: FontWeight.w400, color: Colors.white70),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, 64.h),
          textStyle: TextStyle(
            fontFamily: GoogleFonts.playfairDisplay().fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
          elevation: 4,
          shadowColor: buttonShadow,
        ),
      ),
    );
  }
}

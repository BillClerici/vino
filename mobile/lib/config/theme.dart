import 'package:flutter/material.dart';

class VinoTheme {
  // Gunmetal blue palette
  static const _primary = Color(0xFF2C3E50);       // Gunmetal blue
  static const _secondary = Color(0xFF5DADE2);      // Bright sky accent
  static const _tertiary = Color(0xFF1ABC9C);        // Teal accent
  static const _surface = Color(0xFFF8F9FA);         // Cool white
  static const _surfaceDark = Color(0xFF1A1D23);     // Dark gunmetal

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme(
          brightness: Brightness.light,
          primary: _primary,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFD6E4F0),  // Soft blue-grey
          onPrimaryContainer: const Color(0xFF1A2530),
          secondary: _secondary,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFD4EFFC),
          onSecondaryContainer: const Color(0xFF0D3B5E),
          tertiary: _tertiary,
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFFC8F7ED),
          onTertiaryContainer: const Color(0xFF0A3D32),
          error: const Color(0xFFE74C3C),
          onError: Colors.white,
          errorContainer: const Color(0xFFFDEDEB),
          onErrorContainer: const Color(0xFF5F1A13),
          surface: _surface,
          onSurface: const Color(0xFF2C3E50),
          surfaceContainerHighest: const Color(0xFFECF0F1),
          outline: const Color(0xFFBDC3C7),
          outlineVariant: const Color(0xFFD5DBDB),
          inverseSurface: const Color(0xFF2C3E50),
          onInverseSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFF2C3E50),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Color(0xFF95A5A6),
          indicatorColor: Color(0xFF5DADE2),
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: const Color(0xFF1B3A5C),
          backgroundColor: const Color(0xFF2C3E50),
          surfaceTintColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Colors.white);
            }
            return const IconThemeData(color: Color(0xFF95A5A6));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              );
            }
            return const TextStyle(fontSize: 12, color: Color(0xFF95A5A6));
          }),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          surfaceTintColor: Colors.transparent,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFECF0F1),
          selectedColor: const Color(0xFFD6E4F0),
          labelStyle: const TextStyle(color: Color(0xFF2C3E50)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF5DADE2),
          foregroundColor: Colors.white,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFECF0F1),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme(
          brightness: Brightness.dark,
          primary: _secondary,                          // Bright blue as primary in dark
          onPrimary: const Color(0xFF0D1B2A),
          primaryContainer: const Color(0xFF1B3A5C),
          onPrimaryContainer: const Color(0xFFD6E4F0),
          secondary: _tertiary,
          onSecondary: const Color(0xFF0A2A22),
          secondaryContainer: const Color(0xFF14503F),
          onSecondaryContainer: const Color(0xFFC8F7ED),
          tertiary: const Color(0xFFF39C12),            // Warm amber accent
          onTertiary: Colors.black,
          tertiaryContainer: const Color(0xFF5C3A08),
          onTertiaryContainer: const Color(0xFFFDE8C8),
          error: const Color(0xFFFF6B6B),
          onError: Colors.black,
          errorContainer: const Color(0xFF5F1A13),
          onErrorContainer: const Color(0xFFFDEDEB),
          surface: _surfaceDark,
          onSurface: const Color(0xFFECF0F1),
          surfaceContainerHighest: const Color(0xFF2A2D35),
          outline: const Color(0xFF4A4D55),
          outlineVariant: const Color(0xFF35383F),
          inverseSurface: const Color(0xFFECF0F1),
          onInverseSurface: const Color(0xFF1A1D23),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFF2C3E50),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Color(0xFF95A5A6),
          indicatorColor: Color(0xFF5DADE2),
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: const Color(0xFF1B3A5C),
          backgroundColor: const Color(0xFF2C3E50),
          surfaceTintColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Colors.white);
            }
            return const IconThemeData(color: Color(0xFF95A5A6));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              );
            }
            return const TextStyle(fontSize: 12, color: Color(0xFF95A5A6));
          }),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          surfaceTintColor: Colors.transparent,
          color: const Color(0xFF22252D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF5DADE2),
          foregroundColor: Colors.white,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF35383F),
        ),
      );
}

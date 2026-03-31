// File: lib/app/config/theme/app_theme.dart
// Defines the ThemeData for the application.

import 'package:flutter/material.dart';
import 'package:abra_fleet/app/config/theme/app_colors.dart'; // Import your AppColors

class AppTheme {
  // Prevent instantiation
  AppTheme._();

  // --- Light Theme ---
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: AppColors.primary,
    primaryColorDark: AppColors.primaryDark,
    primaryColorLight: AppColors.primaryLight,
    //scaffoldBackgroundColor: AppColors.backgroundLight,
    // For Material 3, colorScheme is more central
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.textOnPrimary,
      primaryContainer: AppColors.primaryLight, // Or a specific container color
      onPrimaryContainer: AppColors.textPrimary,

      secondary: AppColors.secondary,
      onSecondary: AppColors.textOnSecondary,
      secondaryContainer:
          AppColors.secondaryLight, // Or a specific container color
      onSecondaryContainer: AppColors.textPrimary,

      tertiary: AppColors.accent, // Using accent as tertiary
      onTertiary:
          AppColors.textOnPrimary, // Assuming accent has dark text on it
      tertiaryContainer: AppColors.accentLight,
      onTertiaryContainer: AppColors.textPrimary,

      error: AppColors.error,
      onError: AppColors.textOnError,
      errorContainer: Color(0xFFFCD8DF), // Light red for error container
      onErrorContainer: Color(0xFF5A1623), // Dark red text on error container

      background: AppColors.backgroundLight,
      onBackground: AppColors.textPrimary,

      surface: AppColors.surfaceLight, // Used for Cards, Dialogs, BottomSheets
      onSurface: AppColors.textPrimary,
      surfaceVariant: AppColors
          .lightGrey, // For things like outlined button borders, dividers
      onSurfaceVariant: AppColors.textSecondary,

      outline: AppColors.grey,
      outlineVariant: AppColors.lightGrey, // For less prominent outlines

      // Inverse colors are useful for specific scenarios
      // inversePrimary: AppColors.primaryLight,
      // inverseSurface: AppColors.textPrimary,
      // onInverseSurface: AppColors.backgroundLight,
    ),

    scaffoldBackgroundColor: AppColors.backgroundLight,

    appBarTheme: const AppBarTheme(
      elevation: 1.0, // Subtle shadow
      backgroundColor:
          AppColors.primary, // Or surfaceLight for a more modern look
      foregroundColor: AppColors.textOnPrimary, // Icon and title color
      iconTheme: IconThemeData(color: AppColors.textOnPrimary),
      titleTextStyle: TextStyle(
        color: AppColors.textOnPrimary,
        fontSize: 20.0,
        fontWeight: FontWeight.w600,
      ),
    ),

    textTheme: const TextTheme(
      // Display styles (large, prominent text)
      displayLarge: TextStyle(
          fontSize: 57,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: -0.25),
      displayMedium: TextStyle(
          fontSize: 45,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: 0.0),
      displaySmall: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: 0.0),

      // Headline styles (for page titles, section headers)
      headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: 0.0),
      headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: 0.0),
      headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: 0.0),

      // Title styles (for smaller headings, list item titles)
      titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 0.15),
      titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 0.15),
      titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 0.1),

      // Body styles (for main content text)
      bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: 0.5),
      bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: 0.25),
      bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
          letterSpacing: 0.4),

      // Label styles (for buttons, captions, overlines)
      labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: 0.1), // Often used for button text
      labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 0.5),
      labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
          letterSpacing: 0.5),
    ).apply(
      // Apply a base font family if desired
      // fontFamily: 'YourCustomFont', // Make sure to add font to pubspec.yaml and assets
      displayColor: AppColors.textPrimary,
      bodyColor: AppColors.textPrimary,
    ),

    buttonTheme: ButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      buttonColor: AppColors.primary,
      textTheme: ButtonTextTheme.primary,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        elevation: 2.0,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightGrey.withOpacity(0.5),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: BorderSide.none, // No border by default, rely on fill
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: BorderSide(color: AppColors.grey.withOpacity(0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: const BorderSide(color: AppColors.error, width: 2.0),
      ),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle: const TextStyle(color: AppColors.textSecondary),
    ),

    cardTheme: CardThemeData(
      elevation: 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6.0),
      color: AppColors.surfaceLight,
    ),

    iconTheme: const IconThemeData(
      color: AppColors.textSecondary, // Default icon color
      size: 24.0,
    ),
    primaryIconTheme: const IconThemeData(
      color: AppColors.primary, // Icons that use primary color by context
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.primary.withOpacity(0.1),
      disabledColor: Colors.grey.withOpacity(0.5),
      selectedColor: AppColors.primary,
      secondarySelectedColor: AppColors.secondary,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      labelStyle: const TextStyle(
          color: AppColors.primary, fontWeight: FontWeight.w500),
      secondaryLabelStyle: const TextStyle(
          color: AppColors.textOnSecondary, fontWeight: FontWeight.w500),
      brightness: Brightness.light,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surfaceLight,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      selectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelStyle: const TextStyle(fontSize: 10),
      type: BottomNavigationBarType.fixed,
      elevation: 8.0,
    ),

    // You can define a dark theme similarly if needed
    // static final ThemeData darkTheme = ThemeData(...);
  );
}

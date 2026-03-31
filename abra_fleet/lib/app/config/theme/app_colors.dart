// File: lib/app/config/theme/app_colors.dart
// Defines the color palette for the application.

import 'package:flutter/material.dart';

class AppColors {
  // Prevent instantiation
  AppColors._();

  // --- Primary Palette ---
  // Example: A deep blue for primary actions, app bars, etc.
  static const Color primary = Color(0xFF0D47A1); // Deep Blue
  static const Color primaryDark = Color(0xFF002171); // Darker shade of primary
  static const Color primaryLight = Color(0xFF5472D3); // Lighter shade of primary

  // --- Secondary Palette ---
  // Example: A complementary teal or green for accents, FABs, etc.
  static const Color secondary = Color(0xFF00796B); // Teal
  static const Color secondaryDark = Color(0xFF004D40); // Darker Teal
  static const Color secondaryLight = Color(0xFF48A999); // Lighter Teal

  // --- Accent / Highlight Colors ---
  // Example: An amber or orange for highlights, warnings, or special CTAs.
  static const Color accent = Color(0xFFFFA000); // Amber
  static const Color accentDark = Color(0xFFC67100);
  static const Color accentLight = Color(0xFFFFD149);

  // --- Neutral Colors ---
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color grey = Color(0xFF9E9E9E); // Standard grey
  static const Color lightGrey = Color(0xFFF5F5F5); // For backgrounds, dividers
  static const Color darkGrey = Color(0xFF616161); // For secondary text or icons

  // --- Semantic Colors ---
  static const Color success = Color(0xFF4CAF50); // Green
  static const Color error = Color(0xFFD32F2F);   // Red
  static const Color warning = Color(0xFFFFA000); // Amber (can be same as accent)
  static const Color info = Color(0xFF1976D2);    // Blue

  // --- Text Colors ---
  static const Color textPrimary = Color(0xFF212121); // For primary text
  static const Color textSecondary = Color(0xFF757575); // For secondary text, hints
  static const Color textOnPrimary = white; // Text color on primary background
  static const Color textOnSecondary = white; // Text color on secondary background
  static const Color textOnError = white; // Text color on error background

  // --- Background Colors ---
  static const Color backgroundLight = Color(0xFFFFFFFF); // For light theme background
  static const Color backgroundDark = Color(0xFF121212);  // For dark theme background (Material Design dark)
  static const Color surfaceLight = Color(0xFFFFFFFF); // For card backgrounds in light theme
  static const Color surfaceDark = Color(0xFF1E1E1E);  // For card backgrounds in dark theme

// You can add more specific colors as your app grows, e.g.:
// static const Color vehicleStatusActive = success;
// static const Color vehicleStatusMaintenance = warning;
// static const Color vehicleStatusInactive = error;
}

import 'package:flutter/material.dart';

// ─── SHARED COLOR CONSTANTS ───────────────────────────────────────────────────
// These match BillingMainShell exactly
const kNavyDark   = Color(0xFF0F172A); // darker navy for gradient start
const kNavy       = Color(0xFF1E3A5F); // navy blue for gradient end
const kBlueAccent = Color(0xFF2563EB); // buttons / active highlight
const kWhite      = Color(0xFFFFFFFF); // text on dark background
const kPageBg     = Color(0xFFF8FAFC); // main content background
// ─────────────────────────────────────────────────────────────────────────────

/// A reusable top bar widget that matches the BillingMainShell style.
///
/// Usage — just add to any page's Scaffold:
///
/// ```dart
/// Scaffold(
///   appBar: AppTopBar(title: 'Invoices'),
///   body: ...
/// )
/// ```
///
/// Optional params:
///   - [actions]      → add buttons on the right side
///   - [showBack]     → set to false to hide the back arrow (default: true)
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;

  const AppTopBar({
    Key? key,
    required this.title,
    this.actions,
    this.showBack = true,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [kNavyDark, kNavy],
          ),
        ),
      ),
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Row(
        children: [
          if (showBack)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: kWhite),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
            ),
          if (showBack) const SizedBox(width: 4),
          Text(
            title,
            style: const TextStyle(
              color: kWhite,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: actions,
    );
  }
}
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class SupportSystemScreen extends StatelessWidget {
  const SupportSystemScreen({Key? key}) : super(key: key);

  Future<void> _launchPhoneCall(BuildContext context) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '+918867288076');
    try {
      await launchUrl(phoneUri);
    } catch (e) {
      if (context.mounted) {
        _copyToClipboard(context, '+918867288076', 'Phone number');
      }
    }
  }

  Future<void> _launchWhatsApp(BuildContext context) async {
    final Uri whatsappWeb = Uri.parse('https://wa.me/918867288076');
    try {
      await launchUrl(whatsappWeb, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) _showErrorSnackBar(context, 'Unable to open WhatsApp');
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    const String email = 'support@fleet.abra-travels.com';
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'Support Request', 'body': 'Hello Abra Travels Support Team,\n\n'},
    );
    try {
      await launchUrl(emailUri, mode: LaunchMode.platformDefault);
    } catch (e) {
      if (context.mounted) _copyToClipboard(context, email, 'Email address');
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied!'),
      backgroundColor: Colors.green[700],
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              const Icon(Icons.headset_mic, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Customer Support',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),

        // ── Body ────────────────────────────────────────────────────────────
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Contact cards
                _contactCard(
                  context,
                  icon: Icons.phone,
                  color: const Color(0xFF3B82F6),
                  title: 'Call Us',
                  subtitle: '+91 886-728-8076',
                  onTap: () => _launchPhoneCall(context),
                  onCopy: () => _copyToClipboard(context, '+918867288076', 'Phone number'),
                ),
                const SizedBox(height: 10),
                _contactCard(
                  context,
                  icon: Icons.chat_bubble,
                  color: const Color(0xFF10B981),
                  title: 'WhatsApp',
                  subtitle: 'Chat with us instantly',
                  onTap: () => _launchWhatsApp(context),
                ),
                const SizedBox(height: 10),
                _contactCard(
                  context,
                  icon: Icons.email,
                  color: const Color(0xFFF59E0B),
                  title: 'Email Us',
                  subtitle: 'support@fleet.abra-travels.com',
                  onTap: () => _launchEmail(context),
                  onCopy: () => _copyToClipboard(context, 'support@fleet.abra-travels.com', 'Email'),
                ),

                const SizedBox(height: 16),

                // Availability badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time_rounded, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Available 24/7', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800], fontSize: 13)),
                          Text('Typically responds within a few hours', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Quick help
                Text('Quick Help', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    children: [
                      _helpRow('📋', 'Track your trips in real-time'),
                      _divider(),
                      _helpRow('🚗', 'View assigned drivers and vehicles'),
                      _divider(),
                      _helpRow('📊', 'Check detailed statistics'),
                      _divider(),
                      _helpRow('🆘', 'Use SOS for emergencies'),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Footer
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.favorite, color: Colors.red[400], size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Committed to your satisfaction and safety. Thank you for choosing Abra Travels!',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _contactCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    VoidCallback? onCopy,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (onCopy != null)
                IconButton(
                  icon: Icon(Icons.copy, size: 18, color: Colors.grey[400]),
                  onPressed: onCopy,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[300]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpRow(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.withOpacity(0.12));
}

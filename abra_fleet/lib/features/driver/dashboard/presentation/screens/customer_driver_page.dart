// lib/features/driver/dashboard/presentation/screens/customer_driver_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';


// --- UI Constants - Matching the Dashboard ---
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kWarningColor = Color(0xFFF59E0B);
const Color kScaffoldBackgroundColor = Color(0xFFF1F5F9);
const Color kCardBackgroundColor = Colors.white;
const Color kPrimaryTextColor = Color(0xFF1E293B);
const Color kSecondaryTextColor = Color(0xFF64748B);

class CustomerDriverPage extends StatelessWidget {
  const CustomerDriverPage({Key? key}) : super(key: key);
  
  Future<void> _handleLogout(BuildContext context) async {
    // ... (Same logout logic)
     final authRepository = Provider.of<AuthRepository>(context, listen: false);
    final confirmLogout = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Confirm Logout'),
              content: const Text('Are you sure you want to log out?'),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Logout')),
              ],
            ));
    if (confirmLogout == true && context.mounted) {
      await authRepository.signOut();
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Customers', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: kPrimaryColor,
        actions: [
          IconButton(icon: const Icon(Icons.notifications, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), tooltip: 'Logout', onPressed: () => _handleLogout(context)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurrentPassengersCard(),
            const SizedBox(height: 16),
            _buildCommunicationCard(),
            // const SizedBox(height: 16),
            // _buildEtaManagementCard(),
          ],
        ),
      ),
    );
  }

  // --- Reusable Widgets ---
  Widget _buildCard({required String title, required Widget child, IconData? icon}) {
     // ... (Same card widget)
      return Card(
      elevation: 2.0,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      color: kCardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(children: [
                if (icon != null) Icon(icon, color: kPrimaryTextColor, size: 22),
                if (icon != null) const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: kPrimaryTextColor)),
              ],),
            const SizedBox(height: 15.0),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStyledButton({required VoidCallback onPressed, required String text, required Color backgroundColor, IconData? icon}) {
    // ... (Same button widget)
     return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          elevation: 2,
        ),
      ),
    );
  }
  
  // --- Page Sections ---
  Widget _buildCurrentPassengersCard() {
    return _buildCard(
        title: 'Current Passengers',
        icon: Icons.people,
        child: Column(
          children: [
             _buildCustomerItem(initials: 'SK', name: 'Sarah Kumar', location: 'Cyber City Hub', status: 'Picked Up', statusColor: const Color(0xFFD1FAE5), statusTextColor: const Color(0xFF065F46)),
             const SizedBox(height: 8),
             _buildCustomerItem(initials: 'MR', name: 'Mike Rahman', location: 'DLF Phase 2', status: 'Picked Up', statusColor: const Color(0xFFD1FAE5), statusTextColor: const Color(0xFF065F46)),
             const SizedBox(height: 8),
             _buildCustomerItem(initials: 'LT', name: 'Lisa Thompson', location: 'Sector 29', status: 'Waiting', statusColor: const Color(0xFFFEF3C7), statusTextColor: const Color(0xFF92400E)),
          ],
        ),
    );
  }
  
  Widget _buildCommunicationCard() {
     return _buildCard(
      title: 'Communication',
      icon: Icons.chat,
      child: Column(
        children: [
          _buildFormTextField(label: 'Broadcast Message', hint: 'Type message to all customers...'),
          const SizedBox(height: 16),
          _buildStyledButton(onPressed: () {}, text: 'Send to All', icon: Icons.send, backgroundColor: kPrimaryColor),
          // const SizedBox(height: 8),
          // _buildStyledButton(onPressed: () {}, text: 'Call Customer', icon: Icons.call, backgroundColor: kWarningColor),
        ],
      ),
    );
  }
  
  // Widget _buildEtaManagementCard() {
  //   return _buildCard(
  //     title: 'ETA Management',
  //     icon: Icons.timer,
  //     child: Column(
  //       children: [
  //          _buildFormTextField(label: 'Current ETA', initialValue: '10:30 AM (5 min delay)', readOnly: true),
  //          const SizedBox(height: 16),
  //          _buildStyledButton(onPressed: () {}, text: 'Report Delay', icon: Icons.warning_amber_rounded, backgroundColor: kWarningColor),
  //          const SizedBox(height: 8),
  //          _buildStyledButton(onPressed: () {}, text: 'Share Live Location', icon: Icons.my_location, backgroundColor: kPrimaryColor),
  //       ],
  //     ),
  //   );
  // }
  
  // --- Helper Widgets ---
  Widget _buildCustomerItem({required String initials, required String name, required String location, required String status, required Color statusColor, required Color statusTextColor}) {
    // ... (This widget can remain as is)
     return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8.0)),
      child: Row(
        children: [
          CircleAvatar(radius: 20, backgroundColor: kPrimaryColor, child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: kPrimaryTextColor)),
              const SizedBox(height: 2),
              Text(location, style: const TextStyle(fontSize: 12, color: kSecondaryTextColor)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(10.0)),
            child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusTextColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildFormTextField({required String label, String? hint, String? initialValue, bool readOnly = false}) {
    // ... (This widget can remain as is)
     return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: kPrimaryTextColor, fontSize: 14)),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: initialValue,
          readOnly: readOnly,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: readOnly ? Colors.grey[200] : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: kPrimaryColor, width: 2.0)),
          ),
        ),
      ],
    );
  }
}
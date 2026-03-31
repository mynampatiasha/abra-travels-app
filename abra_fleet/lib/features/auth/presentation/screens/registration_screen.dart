// ============================================================================
// ABRA TRAVELS — PREMIUM REGISTRATION SCREEN
// ============================================================================
// File: lib/features/auth/presentation/screens/registration_screen.dart
// ✅ No left panel — centred layout on all screen sizes
// ✅ Logo + title centred at top
// ✅ Horizontal 4-step row above form
// ✅ Navy glassmorphism — pure white text everywhere
// ✅ All font sizes +2px
// ✅ All existing fields and logic preserved
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';

// ── Brand colors ──────────────────────────────────────────────────────────────
const Color _blueDark   = Color(0xFF0B1F4B);
const Color _blueMid    = Color(0xFF1E3A8A);
const Color _blueLight  = Color(0xFF3B82F6);
const Color _blueAccent = Color(0xFF60A5FA);
const Color _goldAccent = Color(0xFFFBBF24);

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with TickerProviderStateMixin {
  final _formKey          = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final _nameCtrl            = TextEditingController();
  final _emailCtrl           = TextEditingController();
  final _passwordCtrl        = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _phoneCtrl           = TextEditingController();
  final _altPhoneCtrl        = TextEditingController();
  final _companyNameCtrl     = TextEditingController();
  final _deptSearchCtrl      = TextEditingController();
  final _employeeIdCtrl      = TextEditingController();
  final _designationCtrl     = TextEditingController();
  final _branchSearchCtrl    = TextEditingController();
  final _emergencyNameCtrl   = TextEditingController();
  final _emergencyPhoneCtrl  = TextEditingController();

  String? _selectedDepartment;
  String? _selectedBranch;
  String? _selectedRole;
  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _isLoading      = false;
  bool _isDeptOpen     = false;
  bool _isBranchOpen   = false;

  late final AnimationController _orbitCtrl;
  late final AnimationController _entranceCtrl;
  late final Animation<double>   _entranceFade;
  late final Animation<Offset>   _entranceSlide;

  final List<String> _roles = ['driver', 'customer'];

  final List<String> _departments = [
    'Engineering', 'Human Resources', 'Finance', 'Sales',
    'Marketing', 'Operations', 'IT Support', 'Customer Service',
    'Product Management', 'Legal', 'Administration', 'Research & Development',
  ];

  final List<String> _branches = [
    'Bangalore', 'Chennai', 'Hyderabad', 'Mumbai', 'Delhi',
    'Pune', 'Kolkata', 'Ahmedabad', 'Gurgaon', 'Noida',
    'Kochi', 'Coimbatore', 'Indore', 'Bhubaneswar', 'Jaipur',
    'Chandigarh', 'Lucknow', 'Nagpur', 'Vadodara', 'Thiruvananthapuram',
  ];

  List<String> _filteredDepts    = [];
  List<String> _filteredBranches = [];

  @override
  void initState() {
    super.initState();
    _filteredDepts    = _departments;
    _filteredBranches = _branches;

    _orbitCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 20))
      ..repeat();
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _entranceFade  = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _entranceSlide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic));
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _orbitCtrl.dispose();
    _entranceCtrl.dispose();
    for (final c in [
      _nameCtrl, _emailCtrl, _passwordCtrl, _confirmPasswordCtrl,
      _phoneCtrl, _altPhoneCtrl, _companyNameCtrl, _deptSearchCtrl,
      _employeeIdCtrl, _designationCtrl, _branchSearchCtrl,
      _emergencyNameCtrl, _emergencyPhoneCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  void _filterDepts(String q) => setState(() {
    _filteredDepts = q.isEmpty
        ? _departments
        : _departments.where((d) => d.toLowerCase().contains(q.toLowerCase())).toList();
  });

  void _filterBranches(String q) => setState(() {
    _filteredBranches = q.isEmpty
        ? _branches
        : _branches.where((b) => b.toLowerCase().contains(q.toLowerCase())).toList();
  });

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole == null) {
      _showError('Please select your account type');
      return;
    }
    setState(() => _isLoading = true);

    try {
      final authRepository = Provider.of<AuthRepository>(context, listen: false);
      String? phone = _phoneCtrl.text.trim();
      if (phone.isNotEmpty && !phone.startsWith('+')) phone = '+91$phone';

      await authRepository.signUp(
        email:       _emailCtrl.text.trim(),
        password:    _passwordCtrl.text.trim(),
        name:        _nameCtrl.text.trim(),
        role:        _selectedRole!.toLowerCase().trim(),
        phoneNumber: phone,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Account created! You can now sign in.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      String msg = 'Registration failed';
      if (e.toString().contains('User already exists') ||
          e.toString().contains('email-already-in-use')) {
        msg = 'This email is already registered. Please sign in instead.';
      } else if (e.toString().contains('weak-password')) {
        msg = 'Password is too weak. Use at least 6 characters.';
      } else {
        msg = 'Registration failed: ${e.toString()}';
      }
      if (mounted) _showError(msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 4),
    ));
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _orbitCtrl,
              builder: (_, __) => CustomPaint(painter: _RegBgPainter(_orbitCtrl.value)),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _entranceFade,
              child: SlideTransition(
                position: _entranceSlide,
                child: Center(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoBadge(),
                          const SizedBox(height: 24),
                          const Text(
                            'Create Account',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.1,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Join the ABRA Travels network.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                height: 1.5),
                          ),
                          const SizedBox(height: 32),
                          _buildHorizontalSteps(),
                          const SizedBox(height: 32),
                          _buildForm(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Logo badge ─────────────────────────────────────────────────────────────
  Widget _buildLogoBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: _blueAccent.withOpacity(0.45), blurRadius: 20, spreadRadius: 2)],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Image.asset('assets/logo.png', fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ABRA TRAVELS',
                style: TextStyle(color: Colors.white, fontSize: 17,
                    fontWeight: FontWeight.w800, letterSpacing: 2)),
            Text('Fleet Management Platform',
                style: TextStyle(color: Colors.white, fontSize: 10,
                    letterSpacing: 0.8)),
          ],
        ),
      ],
    );
  }

  // ── Horizontal 4-step row ──────────────────────────────────────────────────
  Widget _buildHorizontalSteps() {
    final steps = [
      (Icons.person_add_alt_1_rounded,     '01', 'Register'),
      (Icons.admin_panel_settings_rounded, '02', 'Admin Approval'),
      (Icons.badge_outlined,               '03', 'Role Assigned'),
      (Icons.directions_bus_rounded,       '04', 'Fleet Access'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.15),
                    Colors.white.withOpacity(0.3),
                    Colors.white.withOpacity(0.15),
                  ],
                ),
              ),
            ),
          );
        }
        final s = steps[i ~/ 2];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_blueAccent, _blueLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: _blueAccent.withOpacity(0.4), blurRadius: 12, spreadRadius: 1),
                ],
              ),
              child: Icon(s.$1, color: Colors.white, size: 17),
            ),
            const SizedBox(height: 6),
            Text(s.$2,
                style: const TextStyle(
                    color: _blueAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
            const SizedBox(height: 3),
            Text(s.$3,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ],
        );
      }),
    );
  }

  // ── Form ───────────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionCard(
            icon: Icons.person_outline_rounded,
            title: 'Basic Information',
            children: [
              _field(ctrl: _nameCtrl, label: 'Full Name', icon: Icons.person_rounded, required: true,
                  validator: (v) => v?.isEmpty ?? true ? 'Please enter your full name' : null),
              _field(ctrl: _emailCtrl, label: 'Email Address', icon: Icons.email_outlined,
                  required: true, keyboard: TextInputType.emailAddress,
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Please enter your email';
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v!)) return 'Enter a valid email';
                    return null;
                  }),
              _field(ctrl: _phoneCtrl, label: 'Phone Number', icon: Icons.phone_outlined,
                  required: true, keyboard: TextInputType.phone, hint: '9876543210',
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Please enter phone number';
                    String c = v!.replaceAll(RegExp(r'\s+'), '');
                    if (c.startsWith('+91')) c = c.substring(3);
                    if (c.length != 10 || !RegExp(r'^[6-9]\d{9}$').hasMatch(c)) {
                      return 'Enter a valid 10-digit phone number';
                    }
                    return null;
                  }),
              _field(ctrl: _altPhoneCtrl, label: 'Alternative Phone', icon: Icons.phone_android_outlined,
                  keyboard: TextInputType.phone, hint: 'Optional'),
              _field(ctrl: _passwordCtrl, label: 'Password', icon: Icons.lock_outline_rounded,
                  required: true, obscure: _obscurePass,
                  suffix: IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.white, size: 18),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Please enter a password';
                    if (v!.length < 6) return 'Minimum 6 characters';
                    return null;
                  }),
              _field(ctrl: _confirmPasswordCtrl, label: 'Confirm Password', icon: Icons.lock_outline_rounded,
                  required: true, obscure: _obscureConfirm,
                  suffix: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.white, size: 18),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Please confirm your password';
                    if (v != _passwordCtrl.text) return 'Passwords do not match';
                    return null;
                  }),
            ],
          ),
          const SizedBox(height: 16),

          _sectionCard(
            icon: Icons.business_outlined,
            title: 'Organisation Details',
            children: [
              _field(ctrl: _companyNameCtrl, label: 'Company Name', icon: Icons.business_center_outlined,
                  required: true, hint: 'Enter company name',
                  validator: (v) => v?.isEmpty ?? true ? 'Please enter company name' : null),
              _field(ctrl: _employeeIdCtrl, label: 'Employee ID', icon: Icons.badge_outlined,
                  hint: 'Optional — your employee identification number'),
              _buildDeptDropdown(),
              const SizedBox(height: 16),
              _buildBranchDropdown(),
              const SizedBox(height: 16),
              _field(ctrl: _designationCtrl, label: 'Designation / Position', icon: Icons.work_outline_rounded,
                  hint: 'Optional — your job title'),
            ],
          ),
          const SizedBox(height: 16),

          _sectionCard(
            icon: Icons.emergency_outlined,
            title: 'Emergency Contact',
            subtitle: 'Optional',
            children: [
              _field(ctrl: _emergencyNameCtrl, label: 'Contact Name', icon: Icons.contact_emergency_outlined,
                  hint: 'Full name of emergency contact'),
              _field(ctrl: _emergencyPhoneCtrl, label: 'Contact Phone', icon: Icons.phone_in_talk_outlined,
                  hint: '9876543210', keyboard: TextInputType.phone),
            ],
          ),
          const SizedBox(height: 16),

          _sectionCard(
            icon: Icons.manage_accounts_outlined,
            title: 'Account Type',
            children: [_buildRoleSelector()],
          ),
          const SizedBox(height: 28),

          ElevatedButton.icon(
            onPressed: _isLoading ? null : _register,
            icon: _isLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: Text(_isLoading ? 'Creating Account...' : 'Create Account',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _blueAccent,
              disabledBackgroundColor: _blueAccent.withOpacity(0.5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Already have an account?',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              TextButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.only(left: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Sign In',
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700, color: _goldAccent)),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Section card ───────────────────────────────────────────────────────────
  Widget _sectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _blueAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: _blueAccent, size: 16),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(subtitle,
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ],
          ]),
          const SizedBox(height: 18),
          ...children.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: w,
              )),
        ],
      ),
    );
  }

  // ── Field — pure white text, font +2 ──────────────────────────────────────
  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    String? hint,
    bool required = false,
    bool obscure = false,
    Widget? suffix,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        hintStyle: const TextStyle(color: Colors.white, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _blueAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFB3B3), fontSize: 12),
      ),
    );
  }

  // ── Department dropdown ────────────────────────────────────────────────────
  Widget _buildDeptDropdown() {
    return FormField<String>(
      validator: (_) => _selectedDepartment == null ? 'Please select a department' : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isDeptOpen = !_isDeptOpen),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: state.hasError ? Colors.red.shade300 : Colors.white.withOpacity(0.12),
                ),
              ),
              child: Row(children: [
                const Icon(Icons.category_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedDepartment ?? 'Department *',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                Icon(_isDeptOpen ? Icons.expand_less : Icons.expand_more, color: Colors.white),
              ]),
            ),
          ),
          if (_isDeptOpen) _buildDropdownPanel(
            searchCtrl: _deptSearchCtrl,
            items: _filteredDepts,
            selected: _selectedDepartment,
            icon: Icons.category_outlined,
            onFilter: _filterDepts,
            onSelect: (v) {
              setState(() {
                _selectedDepartment = v;
                _isDeptOpen = false;
                _deptSearchCtrl.clear();
                _filteredDepts = _departments;
              });
              state.didChange(v);
            },
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(state.errorText!,
                  style: const TextStyle(color: Color(0xFFFFB3B3), fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // ── Branch dropdown ────────────────────────────────────────────────────────
  Widget _buildBranchDropdown() {
    return TextFormField(
      controller: _branchSearchCtrl,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: 'Branch / Location *',
        hintText: 'Enter or select city',
        labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        hintStyle: const TextStyle(color: Colors.white, fontSize: 13),
        prefixIcon: const Icon(Icons.location_city_outlined, color: Colors.white, size: 18),
        suffixIcon: IconButton(
          icon: Icon(_isBranchOpen ? Icons.expand_less : Icons.expand_more, color: Colors.white),
          onPressed: () {
            setState(() => _isBranchOpen = !_isBranchOpen);
            if (_isBranchOpen) _filterBranches(_branchSearchCtrl.text);
          },
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _blueAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFB3B3), fontSize: 12),
      ),
      onChanged: (v) {
        setState(() {
          _selectedBranch = v;
          if (_isBranchOpen) _filterBranches(v);
        });
      },
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Please enter your branch / location' : null,
    );
  }

  // ── Shared dropdown panel ──────────────────────────────────────────────────
  Widget _buildDropdownPanel({
    required TextEditingController searchCtrl,
    required List<String> items,
    required String? selected,
    required IconData icon,
    required void Function(String) onFilter,
    required void Function(String) onSelect,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2660),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextFormField(
              controller: searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: const TextStyle(color: Colors.white, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.white, size: 16),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _blueAccent),
                ),
              ),
              onChanged: onFilter,
            ),
          ),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                final isSelected = selected == item;
                return InkWell(
                  onTap: () => onSelect(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? _blueAccent.withOpacity(0.15) : Colors.transparent,
                    ),
                    child: Row(children: [
                      Icon(icon, size: 14, color: isSelected ? _blueAccent : Colors.white),
                      const SizedBox(width: 10),
                      Text(item,
                          style: TextStyle(
                            color: isSelected ? _blueAccent : Colors.white,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          )),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Role selector ──────────────────────────────────────────────────────────
  Widget _buildRoleSelector() {
    return Row(
      children: _roles.map((role) {
        final isSelected = _selectedRole == role;
        final icon = role == 'driver'
            ? Icons.directions_car_rounded
            : Icons.person_outline_rounded;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedRole = role),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: role == _roles.first ? 10 : 0),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? _blueAccent.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? _blueAccent : Colors.white.withOpacity(0.12),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(children: [
                Icon(icon, color: isSelected ? _blueAccent : Colors.white, size: 26),
                const SizedBox(height: 8),
                Text(
                  role[0].toUpperCase() + role.substring(1),
                  style: TextStyle(
                    color: isSelected ? _blueAccent : Colors.white,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Background painter ─────────────────────────────────────────────────────────
class _RegBgPainter extends CustomPainter {
  final double progress;
  _RegBgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0B1F4B), Color(0xFF0D2660), Color(0xFF1A3A8A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()..color = Colors.white.withOpacity(0.025)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 55) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 55) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    for (int i = 0; i < 3; i++) {
      final angle = (progress * math.pi * 2) + (i * math.pi * 2 / 3);
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 55)
        ..color = const Color(0xFF60A5FA).withOpacity(0.09);
      canvas.drawCircle(
        Offset(size.width * 0.5 + size.width * 0.2 * math.cos(angle),
            size.height * 0.3 + size.height * 0.15 * math.sin(angle)),
        70, glow,
      );
    }

    final line = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, const Color(0xFF60A5FA).withOpacity(0.5), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), line);
  }

  @override
  bool shouldRepaint(_RegBgPainter old) => old.progress != progress;
}
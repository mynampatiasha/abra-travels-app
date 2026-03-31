// lib/features/admin/client_management/presentation/screens/add_client_admin.dart
// ✅ COMPLETE - Client onboarding with CSC location, document uploads, all fields

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:abra_fleet/app/config/api_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentEntry {
  String  documentName = '';
  String  documentType = 'other';
  String? expiryDate;
  PlatformFile? file;

  _DocumentEntry();
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AddClientAdminScreen extends StatefulWidget {
  const AddClientAdminScreen({super.key});

  @override
  State<AddClientAdminScreen> createState() => _AddClientAdminScreenState();
}

class _AddClientAdminScreenState extends State<AddClientAdminScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Basic info controllers ──
  final _nameCtrl          = TextEditingController();
  final _emailCtrl         = TextEditingController();
  final _passwordCtrl      = TextEditingController();
  final _phoneCtrl         = TextEditingController();
  final _addressCtrl       = TextEditingController();
  final _contactPersonCtrl = TextEditingController();
  final _branchCtrl        = TextEditingController();
  final _departmentCtrl    = TextEditingController();
  final _gstCtrl           = TextEditingController();
  final _panCtrl           = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting    = false;

  // ── Location ──
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;
  final _areaCtrl = TextEditingController();

  // Search controllers for dropdowns
  final _countrySearchCtrl = TextEditingController();
  final _stateSearchCtrl   = TextEditingController();
  final _citySearchCtrl    = TextEditingController();

  // ── CSC data (loaded from csc_picker or bundled JSON) ──
  // Using a lightweight static approach compatible with any Flutter version
  final List<String> _countries = _CountryData.countries;
  List<String> _states  = [];
  List<String> _cities  = [];

  // ── Documents ──
  final List<_DocumentEntry> _documents = [];

  static const List<String> _docTypes = [
    'company_registration',
    'gst_certificate',
    'agreement',
    'pan_card',
    'basic_details',
    'other',
  ];

  static const Map<String, String> _docTypeLabels = {
    'company_registration': 'Company Registration',
    'gst_certificate':      'GST Certificate',
    'agreement':            'Agreement',
    'pan_card':             'PAN Card',
    'basic_details':        'Basic Details',
    'other':                'Other',
  };

  @override
  void dispose() {
    _nameCtrl.dispose();          _emailCtrl.dispose();
    _passwordCtrl.dispose();      _phoneCtrl.dispose();
    _addressCtrl.dispose();       _contactPersonCtrl.dispose();
    _branchCtrl.dispose();        _departmentCtrl.dispose();
    _gstCtrl.dispose();           _panCtrl.dispose();
    _areaCtrl.dispose();
    _countrySearchCtrl.dispose(); _stateSearchCtrl.dispose();
    _citySearchCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // LOCATION HELPERS
  // ─────────────────────────────────────────────────────────

  void _onCountrySelected(String country) {
    setState(() {
      _selectedCountry = country;
      _selectedState   = null;
      _selectedCity    = null;
      _states = _CountryData.getStates(country);
      _cities = [];
    });
  }

  void _onStateSelected(String state) {
    setState(() {
      _selectedState = state;
      _selectedCity  = null;
      _cities = _CountryData.getCities(_selectedCountry ?? '', state);
    });
  }

  // ─────────────────────────────────────────────────────────
  // SEARCHABLE DROPDOWN
  // ─────────────────────────────────────────────────────────

  Future<String?> _showSearchableDropdown({
    required BuildContext context,
    required String title,
    required List<String> items,
    required TextEditingController searchCtrl,
  }) async {
    searchCtrl.clear();
    List<String> filtered = List.from(items);

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                maxWidth: 400,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  // Search box
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search $title...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setSt(() => filtered = List.from(items));
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) {
                        setSt(() {
                          filtered = items
                              .where((i) => i.toLowerCase().contains(v.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                  ),
                  // List
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text('No results found', style: TextStyle(color: Colors.grey[600])),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, idx) {
                              final item = filtered[idx];
                              return ListTile(
                                dense: true,
                                title: Text(item, style: const TextStyle(fontSize: 14)),
                                onTap: () => Navigator.pop(ctx, item),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // DOCUMENT HELPERS
  // ─────────────────────────────────────────────────────────

  Future<void> _addDocument() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'xls', 'xlsx'],
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      final entry   = _DocumentEntry();
      entry.file    = result.files.first;
      entry.documentName = result.files.first.name;
      _documents.add(entry);
    });
  }

  Future<void> _pickExpiryDate(int index) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _documents[index].expiryDate = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // SUBMIT
  // ─────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCountry == null) {
      _showSnack('Please select a country', Colors.orange);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/clients');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['name']          = _nameCtrl.text.trim()
        ..fields['email']         = _emailCtrl.text.trim()
        ..fields['password']      = _passwordCtrl.text.trim()
        ..fields['phoneNumber']   = _phoneCtrl.text.trim()
        ..fields['address']       = _addressCtrl.text.trim()
        ..fields['contactPerson'] = _contactPersonCtrl.text.trim()
        ..fields['branch']        = _branchCtrl.text.trim()
        ..fields['department']    = _departmentCtrl.text.trim()
        ..fields['gstNumber']     = _gstCtrl.text.trim()
        ..fields['panNumber']     = _panCtrl.text.trim()
        ..fields['country']       = _selectedCountry ?? ''
        ..fields['state']         = _selectedState  ?? ''
        ..fields['city']          = _selectedCity   ?? ''
        ..fields['area']          = _areaCtrl.text.trim();

      // Document metadata
      final metaList = _documents.map((d) => {
        'documentName': d.documentName,
        'documentType': d.documentType,
        'expiryDate':   d.expiryDate ?? '',
      }).toList();
      request.fields['documentMetadata'] = json.encode(metaList);

      // Attach files
      for (final doc in _documents) {
        if (doc.file?.bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'documents',
              doc.file!.bytes!,
              filename: doc.file!.name,
              contentType: MediaType.parse(_mimeType(doc.file!.extension ?? 'pdf')),
            ),
          );
        } else if (doc.file?.path != null) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'documents',
              doc.file!.path!,
              contentType: MediaType.parse(_mimeType(doc.file!.extension ?? 'pdf')),
            ),
          );
        }
      }

      final streamed = await request.send();
      final resp     = await http.Response.fromStream(streamed);
      final data     = json.decode(resp.body);

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        if (mounted) {
          _showSnack('✅ Client "${_nameCtrl.text.trim()}" created successfully!', Colors.green);
          await Future.delayed(const Duration(milliseconds: 400));
          if (mounted) Navigator.pop(context, true);
        }
      } else {
        throw Exception(data['message'] ?? 'Failed to create client');
      }
    } catch (e) {
      if (mounted) _showSnack('❌ ${e.toString()}', Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _mimeType(String ext) {
    const map = {
      'pdf':  'application/pdf',
      'jpg':  'image/jpeg',
      'jpeg': 'image/jpeg',
      'png':  'image/png',
      'doc':  'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls':  'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };
    return map[ext.toLowerCase()] ?? 'application/octet-stream';
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 4)),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Add New Client', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionCard(
                icon: Icons.business,
                title: 'Company Information',
                children: [
                  _field(_nameCtrl,          'Company Name *',          Icons.business,     required: true),
                  _field(_contactPersonCtrl, 'Contact Person Name *',   Icons.person,       required: true),
                  _field(_emailCtrl,         'Email Address *',         Icons.email,        required: true, keyboardType: TextInputType.emailAddress),
                  _field(_passwordCtrl,      'Password *',              Icons.lock,         required: true, isPassword: true),
                  _field(_phoneCtrl,         'Phone Number *',          Icons.phone,        required: true, keyboardType: TextInputType.phone),
                  _field(_departmentCtrl,    'Department',              Icons.work_outline),
                  _field(_branchCtrl,        'Branch',                  Icons.location_city),
                  _field(_addressCtrl,       'Address',                 Icons.location_on,  maxLines: 2),
                  _field(_gstCtrl,           'GST Number (Optional)',   Icons.receipt_long, caps: TextCapitalization.characters),
                  _field(_panCtrl,           'PAN Number (Optional)',   Icons.credit_card,  caps: TextCapitalization.characters),
                ],
              ),
              const SizedBox(height: 20),
              _sectionCard(
                icon: Icons.location_on,
                title: 'Location (Country → State → City → Area)',
                children: [
                  // Country
                  _locationTile(
                    label:   'Country *',
                    value:   _selectedCountry,
                    hint:    'Select Country',
                    icon:    Icons.public,
                    onTap:   () async {
                      final val = await _showSearchableDropdown(
                        context:    context,
                        title:      'Country',
                        items:      _countries,
                        searchCtrl: _countrySearchCtrl,
                      );
                      if (val != null) _onCountrySelected(val);
                    },
                  ),
                  // State
                  _locationTile(
                    label:    'State *',
                    value:    _selectedState,
                    hint:     _selectedCountry == null ? 'Select Country first' : 'Select State',
                    icon:     Icons.map,
                    enabled:  _selectedCountry != null && _states.isNotEmpty,
                    onTap:    () async {
                      if (_selectedCountry == null) return;
                      final val = await _showSearchableDropdown(
                        context:    context,
                        title:      'State',
                        items:      _states,
                        searchCtrl: _stateSearchCtrl,
                      );
                      if (val != null) _onStateSelected(val);
                    },
                  ),
                  // City
                  _locationTile(
                    label:    'City',
                    value:    _selectedCity,
                    hint:     _selectedState == null ? 'Select State first' : 'Select City',
                    icon:     Icons.location_city,
                    enabled:  _selectedState != null,
                    onTap:    () async {
                      if (_selectedState == null) return;
                      final val = await _showSearchableDropdown(
                        context:    context,
                        title:      'City',
                        items:      _cities,
                        searchCtrl: _citySearchCtrl,
                      );
                      if (val != null) setState(() => _selectedCity = val);
                    },
                  ),
                  // Area (free text)
                  _field(_areaCtrl, 'Area / Locality', Icons.near_me),
                ],
              ),
              const SizedBox(height: 20),
              _sectionCard(
                icon: Icons.folder_open,
                title: 'Documents',
                trailing: ElevatedButton.icon(
                  onPressed: _addDocument,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Document'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                children: [
                  if (_documents.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload_outlined, color: Colors.grey[400], size: 32),
                          const SizedBox(width: 12),
                          Text('No documents added yet\nTap "Add Document" to upload',
                            style: TextStyle(color: Colors.grey[500]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(_documents.length, (i) => _buildDocumentTile(i)),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _isSubmitting ? 'Creating Client...' : 'Create Client',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // DOCUMENT TILE
  // ─────────────────────────────────────────────────────────

  Widget _buildDocumentTile(int index) {
    final doc = _documents[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(Icons.insert_drive_file, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc.file?.name ?? 'Document ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                onPressed: () => setState(() => _documents.removeAt(index)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Document name input
          TextField(
            decoration: const InputDecoration(
              labelText: 'Document Name *',
              border: OutlineInputBorder(),
              isDense: true,
              fillColor: Colors.white,
              filled: true,
            ),
            controller: TextEditingController(text: doc.documentName)
              ..selection = TextSelection.collapsed(offset: doc.documentName.length),
            onChanged: (v) => _documents[index].documentName = v,
          ),
          const SizedBox(height: 10),
          // Document type dropdown
          DropdownButtonFormField<String>(
            value: doc.documentType,
            decoration: const InputDecoration(
              labelText: 'Document Type',
              border: OutlineInputBorder(),
              isDense: true,
              fillColor: Colors.white,
              filled: true,
            ),
            items: _docTypes.map((t) => DropdownMenuItem(
              value: t,
              child: Text(_docTypeLabels[t] ?? t, style: const TextStyle(fontSize: 13)),
            )).toList(),
            onChanged: (v) => setState(() => _documents[index].documentType = v ?? 'other'),
          ),
          const SizedBox(height: 10),
          // Expiry date
          InkWell(
            onTap: () => _pickExpiryDate(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey[400]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    doc.expiryDate ?? 'Select Expiry Date (Optional)',
                    style: TextStyle(
                      fontSize: 13,
                      color: doc.expiryDate != null ? Colors.black87 : Colors.grey[500],
                    ),
                  ),
                  const Spacer(),
                  if (doc.expiryDate != null)
                    GestureDetector(
                      onTap: () => setState(() => _documents[index].expiryDate = null),
                      child: const Icon(Icons.clear, size: 16, color: Colors.red),
                    ),
                ],
              ),
            ),
          ),
          if (doc.file != null) ...[
            const SizedBox(height: 8),
            Text(
              '📎 ${doc.file!.name}  •  ${_humanSize(doc.file!.size)}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  String _humanSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  // ─────────────────────────────────────────────────────────
  // WIDGETS
  // ─────────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1976D2)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children.map((w) => Padding(padding: const EdgeInsets.only(bottom: 14), child: w)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = false,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    TextCapitalization caps = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      maxLines: isPassword ? 1 : maxLines,
      textCapitalization: caps,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      validator: required
          ? (v) {
              if (v == null || v.trim().isEmpty) return '$label is required';
              if (label.contains('Email') && !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'Enter a valid email';
              if (label.contains('Password') && v.trim().length < 6) return 'Minimum 6 characters';
              if (label.contains('Phone') && v.trim().length < 10) return 'Enter valid phone number';
              return null;
            }
          : null,
    );
  }

  Widget _locationTile({
    required String label,
    required String? value,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: enabled ? Colors.grey[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: enabled ? Colors.grey[400]! : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: enabled ? Colors.grey[700] : Colors.grey[400]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(
                    value ?? hint,
                    style: TextStyle(
                      fontSize: 14,
                      color: value != null ? Colors.black87 : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down, color: enabled ? Colors.grey[700] : Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATIC CSC DATA (lightweight, no external package needed)
// Replace or extend as needed. Uses a small but representative dataset.
// ─────────────────────────────────────────────────────────────────────────────

class _CountryData {
  static const List<String> countries = [
    'Afghanistan','Albania','Algeria','Argentina','Australia','Austria','Bangladesh',
    'Belgium','Brazil','Canada','Chile','China','Colombia','Czech Republic','Denmark',
    'Egypt','Ethiopia','Finland','France','Germany','Ghana','Greece','Hong Kong',
    'Hungary','India','Indonesia','Iran','Iraq','Ireland','Israel','Italy','Japan',
    'Jordan','Kenya','Malaysia','Mexico','Morocco','Myanmar','Nepal','Netherlands',
    'New Zealand','Nigeria','Norway','Pakistan','Philippines','Poland','Portugal',
    'Qatar','Romania','Russia','Saudi Arabia','Singapore','South Africa','South Korea',
    'Spain','Sri Lanka','Sweden','Switzerland','Taiwan','Tanzania','Thailand','Turkey',
    'Ukraine','United Arab Emirates','United Kingdom','United States','Vietnam',
  ];

  static const Map<String, List<String>> _stateMap = {
    'India': [
      'Andhra Pradesh','Arunachal Pradesh','Assam','Bihar','Chhattisgarh','Goa',
      'Gujarat','Haryana','Himachal Pradesh','Jharkhand','Karnataka','Kerala',
      'Madhya Pradesh','Maharashtra','Manipur','Meghalaya','Mizoram','Nagaland',
      'Odisha','Punjab','Rajasthan','Sikkim','Tamil Nadu','Telangana','Tripura',
      'Uttar Pradesh','Uttarakhand','West Bengal',
      'Delhi','Chandigarh','Puducherry','Jammu & Kashmir','Ladakh',
    ],
    'United States': [
      'Alabama','Alaska','Arizona','Arkansas','California','Colorado','Connecticut',
      'Delaware','Florida','Georgia','Hawaii','Idaho','Illinois','Indiana','Iowa',
      'Kansas','Kentucky','Louisiana','Maine','Maryland','Massachusetts','Michigan',
      'Minnesota','Mississippi','Missouri','Montana','Nebraska','Nevada',
      'New Hampshire','New Jersey','New Mexico','New York','North Carolina',
      'North Dakota','Ohio','Oklahoma','Oregon','Pennsylvania','Rhode Island',
      'South Carolina','South Dakota','Tennessee','Texas','Utah','Vermont',
      'Virginia','Washington','West Virginia','Wisconsin','Wyoming',
    ],
    'United Kingdom': ['England','Scotland','Wales','Northern Ireland'],
    'Australia': [
      'New South Wales','Victoria','Queensland','South Australia',
      'Western Australia','Tasmania','Northern Territory','Australian Capital Territory',
    ],
    'Canada': [
      'Alberta','British Columbia','Manitoba','New Brunswick',
      'Newfoundland and Labrador','Nova Scotia','Ontario','Prince Edward Island',
      'Quebec','Saskatchewan','Northwest Territories','Nunavut','Yukon',
    ],
    'Germany': [
      'Bavaria','North Rhine-Westphalia','Baden-Württemberg','Lower Saxony',
      'Hesse','Saxony','Rhineland-Palatinate','Saxony-Anhalt','Thuringia',
      'Brandenburg','Hamburg','Mecklenburg-Vorpommern','Saarland',
      'Schleswig-Holstein','Bremen','Berlin',
    ],
  };

  // Districts / Cities per Indian state + US/other states
  static const Map<String, Map<String, List<String>>> _cityMap = {
    'India': {
      'Karnataka': [
        'Bengaluru Urban','Bengaluru Rural','Mysuru','Mangaluru','Hubballi-Dharwad',
        'Belagavi','Davangere','Ballari','Kalaburagi','Shivamogga','Tumakuru',
        'Raichur','Vijayapura','Hassan','Dharwad','Uttara Kannada','Chikkamagaluru',
        'Udupi','Kodagu','Mandya','Chamrajnagar','Chitradurga','Davanagere',
        'Gadag','Haveri','Koppal','Ramanagara','Yadgir','Bidar','Bagalkote','Kolar',
        'Chikkaballapur','Bengaluru','Mysore','Mangalore','Hubli','Gulbarga',
      ],
      'Maharashtra': [
        'Mumbai City','Mumbai Suburban','Pune','Nagpur','Nashik','Aurangabad',
        'Solapur','Kolhapur','Amravati','Thane','Raigad','Satara','Sangli',
        'Jalgaon','Dhule','Nandurbar','Ahmednagar','Beed','Latur','Osmanabad',
        'Nanded','Yavatmal','Akola','Washim','Buldhana','Wardha','Bhandara',
        'Gondia','Chandrapur','Gadchiroli','Ratnagiri','Sindhudurg','Palghar',
      ],
      'Tamil Nadu': [
        'Chennai','Coimbatore','Madurai','Tiruchirappalli','Salem','Tirunelveli',
        'Tiruppur','Vellore','Erode','Thoothukkudi','Dindigul','Thanjavur',
        'Ranipet','Sivaganga','Virudhunagar','Nagapattinam','Cuddalore',
        'Kancheepuram','Villupuram','Perambalur','Ariyalur','Karur',
        'Namakkal','Nilgiris','Pudukkottai','Ramanathapuram','Tenkasi',
        'Tirupattur','Tiruvannamalai','Tiruvarur','Krishnagiri','Dharmapuri',
        'Kallakurichi','Chengalpattu','Mayiladuthurai',
      ],
      'Telangana': [
        'Hyderabad','Warangal Urban','Warangal Rural','Nizamabad','Karimnagar',
        'Khammam','Nalgonda','Medak','Rangareddy','Mahabubnagar','Adilabad',
        'Siddipet','Suryapet','Yadadri Bhuvanagiri','Jagtial','Jangaon',
        'Jayashankar Bhupalpally','Jogulamba Gadwal','Kamareddy','Kumuram Bheem',
        'Mahabubabad','Mancherial','Medchal-Malkajgiri','Mulugu','Nagarkurnool',
        'Narayanpet','Nirmal','Nizamabad','Peddapalli','Rajanna Sircilla',
        'Sangareddy','Vikarabad','Wanaparthy','Hanamkonda',
      ],
      'Andhra Pradesh': [
        'Visakhapatnam','Vijayawada','Guntur','Nellore','Kurnool','Rajahmundry',
        'Kakinada','Tirupati','Anantapur','Kadapa','Krishna','East Godavari',
        'West Godavari','Chittoor','Srikakulam','Vizianagaram','Prakasam',
        'Sri Potti Sriramulu Nellore','YSR Kadapa','Sri Sathya Sai',
        'Palnadu','Bapatla','Eluru','Alluri Sitharama Raju','Anakapalli',
        'Konaseema','Nandyal','Tirupati',
      ],
      'Kerala': [
        'Thiruvananthapuram','Kollam','Pathanamthitta','Alappuzha','Kottayam',
        'Idukki','Ernakulam','Thrissur','Palakkad','Malappuram','Kozhikode',
        'Wayanad','Kannur','Kasaragod',
      ],
      'Gujarat': [
        'Ahmedabad','Surat','Vadodara','Rajkot','Bhavnagar','Jamnagar',
        'Junagadh','Gandhinagar','Anand','Mehsana','Kheda','Patan',
        'Banaskantha','Sabarkantha','Aravalli','Mahisagar','Panchmahal',
        'Dahod','Vadodara','Chhota Udaipur','Narmada','Bharuch','Surat',
        'Tapi','Navsari','Valsad','Dang','Amreli','Botad','Gir Somnath',
        'Porbandar','Devbhumi Dwarka','Morbi','Surendranagar',
      ],
      'West Bengal': [
        'Kolkata','Howrah','Hugli','North 24 Parganas','South 24 Parganas',
        'Purba Medinipur','Paschim Medinipur','Bankura','Purulia','Birbhum',
        'Bardhaman','Nadia','Murshidabad','Malda','Uttar Dinajpur','Dakshin Dinajpur',
        'Jalpaiguri','Darjeeling','Alipurduar','Cooch Behar','Kalimpong',
        'Jhargram','Purba Bardhaman','Paschim Bardhaman',
      ],
      'Uttar Pradesh': [
        'Lucknow','Kanpur','Agra','Varanasi','Meerut','Prayagraj','Ghaziabad',
        'Noida','Bareilly','Aligarh','Moradabad','Saharanpur','Gorakhpur',
        'Firozabad','Jhansi','Muzaffarnagar','Mathura','Rampur','Shahjahanpur',
        'Farrukhabad','Amroha','Hapur','Etawah','Mirzapur','Bulandshahr',
        'Sambhal','Badaun','Lakhimpur Kheri','Rae Bareli','Unnao','Hardoi',
        'Sitapur','Bahraich','Gonda','Faizabad','Ambedkar Nagar','Sultanpur',
        'Azamgarh','Jaunpur','Ballia','Deoria','Kushinagar','Maharajganj',
        'Sant Kabir Nagar','Basti','Siddharth Nagar','Shravasti','Balrampur',
        'Pratapgarh','Kaushambi','Chitrakoot','Banda','Hamirpur','Mahoba',
        'Jalaun','Lalitpur','Etah','Kannauj','Mainpuri','Auraiya','Kanpur Dehat',
        'Fatehpur','Hathras','Agra','Mathura','Firozabad',
      ],
      'Rajasthan': [
        'Jaipur','Jodhpur','Udaipur','Kota','Bikaner','Ajmer','Bharatpur',
        'Alwar','Sri Ganganagar','Sikar','Pali','Barmer','Nagaur','Chittorgarh',
        'Jhunjhunu','Bhilwara','Hanumangarh','Dungarpur','Jalore','Bundi',
        'Tonk','Sawai Madhopur','Karauli','Dholpur','Dausa','Sirohi','Banswara',
        'Churu','Jhalawar','Baran','Rajsamand','Pratapgarh',
      ],
      'Madhya Pradesh': [
        'Bhopal','Indore','Jabalpur','Gwalior','Ujjain','Sagar','Dewas',
        'Satna','Ratlam','Rewa','Murwara','Singrauli','Burhanpur','Khandwa',
        'Bhind','Chhindwara','Guna','Shivpuri','Vidisha','Chhatarpur',
        'Damoh','Mandsaur','Khargone','Neemuch','Pithampur','Narmadapuram',
        'Balaghat','Seoni','Mandla','Dindori','Tikamgarh','Panna','Umaria',
        'Katni','Shahdol','Anuppur','Sidhi','Singrauli','Agar Malwa','Alirajpur',
        'Ashoknagar','Barwani','Betul','Bhind','Bhopal','Burhanpur',
      ],
      'Punjab': [
        'Amritsar','Ludhiana','Jalandhar','Patiala','Bathinda','Mohali',
        'Firozpur','Hoshiarpur','Gurdaspur','Roopnagar','Moga','Muktsar',
        'Fazilka','Faridkot','Mansa','Barnala','Sangrur','Fatehgarh Sahib',
        'Nawanshahr','Tarn Taran','Kapurthala','Pathankot',
      ],
      'Haryana': [
        'Gurgaon','Faridabad','Hisar','Rohtak','Panipat','Ambala',
        'Yamunanagar','Sonipat','Jhajjar','Bhiwani','Sirsa','Fatehabad',
        'Jind','Kaithal','Karnal','Kurukshetra','Mahendragarh','Mewat',
        'Palwal','Panchkula','Rewari',
      ],
      'Delhi': [
        'Central Delhi','East Delhi','New Delhi','North Delhi','North East Delhi',
        'North West Delhi','Shahdara','South Delhi','South East Delhi',
        'South West Delhi','West Delhi',
      ],
      'Bihar': [
        'Patna','Gaya','Bhagalpur','Muzaffarpur','Purnia','Darbhanga',
        'Bihar Sharif','Arrah','Begusarai','Katihar','Munger','Chhapra',
        'Danapur','Bettiah','Saharsa','Hajipur','Dehri','Siwan','Motihari',
        'Nawada','Bagaha','Buxar','Kishanganj','Sitamarhi','Jhanjharpur',
        'Supaul','Madhepura','Araria','Aurangabad','Jehanabad','Gaya',
      ],
      'Odisha': [
        'Bhubaneswar','Cuttack','Rourkela','Brahmapur','Sambalpur','Puri',
        'Balasore','Bhadrak','Baripada','Jharsuguda','Jeypore','Angul',
        'Dhenkanal','Keonjhar','Kendrapara','Jagatsinghpur','Jajpur',
        'Khurda','Nayagarh','Ganjam','Gajapati','Phulbani','Boudh',
        'Sonapur','Bargarh','Bolangir','Nuapada','Kalahandi','Nabarangpur',
        'Rayagada','Koraput','Malkangiri','Kandhamal','Deogarh','Sundargarh',
        'Mayurbhanj',
      ],
      'Assam': [
        'Guwahati','Silchar','Dibrugarh','Jorhat','Nagaon','Tinsukia',
        'Tezpur','Bongaigaon','Dhubri','Diphu','North Lakhimpur','Sivasagar',
        'Goalpara','Barpeta','Kamrup','Kamrup Metropolitan','Sonitpur',
        'Darrang','Morigaon','Hojai','Dima Hasao','Karbi Anglong',
        'West Karbi Anglong','Majuli','South Salmara-Mankachar',
        'Biswanath','Cachar','Hailakandi','Karimganj',
      ],
      'Himachal Pradesh': [
        'Shimla','Mandi','Solan','Dharamshala','Kullu','Hamirpur',
        'Una','Bilaspur','Chamba','Kinnaur','Lahaul and Spiti','Sirmaur',
      ],
      'Uttarakhand': [
        'Dehradun','Haridwar','Roorkee','Haldwani','Rudrapur','Kashipur',
        'Rishikesh','Kotdwar','Almora','Pithoragarh','Pauri Garhwal',
        'Tehri Garhwal','Uttarkashi','Chamoli','Rudraprayag','Bageshwar',
        'Champawat','Nainital','Udham Singh Nagar',
      ],
      'Jharkhand': [
        'Ranchi','Jamshedpur','Dhanbad','Bokaro','Hazaribagh','Giridih',
        'Ramgarh','Deoghar','Dumka','Gumla','Simdega','Lohardaga',
        'Pakur','Jamtara','Sahibganj','Godda','Chatra','Palamu','Garhwa',
        'Latehar','Khunti','West Singhbhum','East Singhbhum','Saraikela Kharsawan',
      ],
      'Chhattisgarh': [
        'Raipur','Bhilai','Bilaspur','Korba','Durg','Rajnandgaon','Jagdalpur',
        'Ambikapur','Raigarh','Dhamtari','Mahasamund','Baloda Bazar','Mungeli',
        'Bemetara','Kabirdham','Balod','Gariaband','Kondagaon','Narayanpur',
        'Bijapur','Sukma','Dantewada','Bastar',
      ],
      'Goa': ['North Goa','South Goa'],
      'Meghalaya': [
        'Shillong','East Khasi Hills','West Khasi Hills','South West Khasi Hills',
        'Ri Bhoi','East Jaintia Hills','West Jaintia Hills','East Garo Hills',
        'West Garo Hills','South Garo Hills','North Garo Hills',
        'Eastern West Khasi Hills',
      ],
      'Manipur': [
        'Imphal West','Imphal East','Thoubal','Bishnupur','Churachandpur',
        'Chandel','Senapati','Ukhrul','Tamenglong','Jiribam','Kakching',
        'Kangpokpi','Noney','Pherzawl','Tengnoupal',
      ],
      'Jammu & Kashmir': [
        'Srinagar','Jammu','Anantnag','Baramulla','Pulwama','Shopian',
        'Budgam','Ganderbal','Bandipora','Kupwara','Kulgam','Doda',
        'Kishtwar','Kathua','Udhampur','Reasi','Samba','Ramban','Rajouri','Poonch',
      ],
      'Sikkim': ['East Sikkim','West Sikkim','North Sikkim','South Sikkim','Pakyong','Soreng'],
      'Mizoram': ['Aizawl','Lunglei','Champhai','Serchhip','Kolasib','Lawngtlai','Mamit','Siaha'],
      'Nagaland': [
        'Kohima','Dimapur','Mokokchung','Tuensang','Wokha','Zunheboto',
        'Mon','Phek','Kiphire','Longleng','Peren',
      ],
      'Tripura': [
        'West Tripura','East Tripura','South Tripura','North Tripura',
        'Dhalai','Gomati','Khowai','Sipahijala','Unakoti',
      ],
      'Arunachal Pradesh': [
        'Itanagar','Tawang','West Kameng','East Kameng','Papum Pare',
        'Kurung Kumey','Kra Daadi','Lower Subansiri','Upper Subansiri',
        'West Siang','East Siang','Siang','Upper Siang','Dibang Valley',
        'Lower Dibang Valley','Anjaw','Lohit','Namsai','Changlang',
        'Tirap','Longding','Pakke-Kessang','Lepa Rada','Shi Yomi',
        'Kamle','East Kameng','Capital Complex Itanagar',
      ],
      'Puducherry': ['Puducherry','Karaikal','Mahe','Yanam'],
    },
    'United States': {
      'California': ['Los Angeles','San Francisco','San Diego','Sacramento','San Jose','Fresno','Oakland','Long Beach','Bakersfield','Anaheim'],
      'New York':   ['New York City','Buffalo','Rochester','Albany','Syracuse','Yonkers','White Plains','Binghamton'],
      'Texas':      ['Houston','Dallas','Austin','San Antonio','Fort Worth','El Paso','Arlington','Corpus Christi'],
      'Florida':    ['Miami','Orlando','Tampa','Jacksonville','Fort Lauderdale','St. Petersburg','Hialeah','Tallahassee'],
      'Illinois':   ['Chicago','Springfield','Naperville','Rockford','Peoria','Joliet','Aurora'],
      'Washington': ['Seattle','Spokane','Tacoma','Vancouver','Bellevue','Kirkland'],
      'Georgia':    ['Atlanta','Columbus','Augusta','Savannah','Athens','Macon'],
    },
    'United Kingdom': {
      'England': ['London','Manchester','Birmingham','Leeds','Liverpool','Newcastle','Sheffield','Bristol','Leicester','Nottingham'],
      'Scotland': ['Edinburgh','Glasgow','Aberdeen','Dundee','Inverness'],
      'Wales':    ['Cardiff','Swansea','Newport','Bangor'],
      'Northern Ireland': ['Belfast','Derry','Lisburn','Newry'],
    },
    'Australia': {
      'New South Wales': ['Sydney','Newcastle','Wollongong','Central Coast','Maitland'],
      'Victoria':        ['Melbourne','Geelong','Ballarat','Bendigo','Launceston'],
      'Queensland':      ['Brisbane','Gold Coast','Sunshine Coast','Townsville','Cairns'],
      'South Australia': ['Adelaide','Mount Gambier','Whyalla','Port Augusta'],
      'Western Australia': ['Perth','Fremantle','Bunbury','Geraldton','Kalgoorlie'],
    },
  };

  static List<String> getStates(String country) => _stateMap[country] ?? [];
  static List<String> getCities(String country, String state) => _cityMap[country]?[state] ?? [];
}
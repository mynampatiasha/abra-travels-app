// lib/features/admin/client_management/edit_client_admin.dart
// ✅ COMPLETE - Edit Client Screen with all fields + document upload

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/models/client_model.dart';
import 'package:abra_fleet/core/services/client_service.dart';

class EditClientAdminScreen extends StatefulWidget {
  final ClientModel client;

  const EditClientAdminScreen({
    super.key,
    required this.client,
  });

  @override
  State<EditClientAdminScreen> createState() => _EditClientAdminScreenState();
}

class _EditClientAdminScreenState extends State<EditClientAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clientService = ClientService();

  // Controllers - pre-filled with existing data
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contactPersonCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _departmentCtrl;
  late final TextEditingController _branchCtrl;
  late final TextEditingController _gstCtrl;
  late final TextEditingController _panCtrl;
  late final TextEditingController _countryCtrl;
  late final TextEditingController _stateCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _areaCtrl;

  String _status = 'active';
  bool _isLoading = false;

  // New documents to upload
  final List<ClientUploadDocument> _newDocuments = [];

  @override
  void initState() {
    super.initState();
    // Pre-fill all fields with existing client data
    _nameCtrl          = TextEditingController(text: widget.client.name);
    _contactPersonCtrl = TextEditingController(text: widget.client.contactPerson ?? '');
    _emailCtrl         = TextEditingController(text: widget.client.email);
    _phoneCtrl         = TextEditingController(text: widget.client.phone);
    _addressCtrl       = TextEditingController(text: widget.client.address ?? '');
    _departmentCtrl    = TextEditingController(text: widget.client.department ?? '');
    _branchCtrl        = TextEditingController(text: widget.client.branch ?? '');
    _gstCtrl           = TextEditingController(text: widget.client.gstNumber ?? '');
    _panCtrl           = TextEditingController(text: widget.client.panNumber ?? '');
    _countryCtrl       = TextEditingController(text: widget.client.location.country);
    _stateCtrl         = TextEditingController(text: widget.client.location.state);
    _cityCtrl          = TextEditingController(text: widget.client.location.city);
    _areaCtrl          = TextEditingController(text: widget.client.location.area);
    _status            = widget.client.status;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactPersonCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _departmentCtrl.dispose();
    _branchCtrl.dispose();
    _gstCtrl.dispose();
    _panCtrl.dispose();
    _countryCtrl.dispose();
    _stateCtrl.dispose();
    _cityCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // SAVE
  // ─────────────────────────────────────────────────────────

  Future<void> _saveChanges() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final updateData = {
        'name':          _nameCtrl.text.trim(),
        'contactPerson': _contactPersonCtrl.text.trim(),
        'email':         _emailCtrl.text.trim(),
        'phone':         _phoneCtrl.text.trim(),
        'address':       _addressCtrl.text.trim(),
        'department':    _departmentCtrl.text.trim(),
        'branch':        _branchCtrl.text.trim(),
        'gstNumber':     _gstCtrl.text.trim(),
        'panNumber':     _panCtrl.text.trim(),
        'status':        _status,
        'location': {
          'country': _countryCtrl.text.trim(),
          'state':   _stateCtrl.text.trim(),
          'city':    _cityCtrl.text.trim(),
          'area':    _areaCtrl.text.trim(),
        },
      };

      await _clientService.updateClient(
        widget.client.id,
        updateData,
        newDocuments: _newDocuments.isNotEmpty ? _newDocuments : null,
      );

      if (mounted) {
        _snack('✅ Client updated successfully', Colors.green);
        Navigator.pop(context, true); // Return true to trigger refresh
      }
    } catch (e) {
      if (mounted) {
        _snack('❌ Error: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // DOCUMENT UPLOAD
  // ─────────────────────────────────────────────────────────

  Future<void> _pickDocuments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,  // ← CRITICAL: Load bytes for web compatibility
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'xls', 'xlsx'],
      );

      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        // Only check bytes (path is not available on web)
        if (file.bytes != null) {
          // Show dialog to get document name and type
          final docInfo = await _showDocumentInfoDialog(file.name);
          if (docInfo == null) continue;

          setState(() {
            _newDocuments.add(ClientUploadDocument(
              bytes:        file.bytes,  // Always use bytes
              path:         null,        // Don't use path on web
              filename:     file.name,
              mimeType:     _getMimeType(file.extension ?? ''),
              documentName: docInfo['name']!,
              documentType: docInfo['type']!,
              expiryDate:   docInfo['expiry'],
            ));
          });
        }
      }

      if (_newDocuments.isNotEmpty) {
        _snack('✅ ${_newDocuments.length} document(s) added', Colors.green);
      }
    } catch (e) {
      _snack('❌ Error picking files: $e', Colors.red);
    }
  }

  Future<Map<String, String>?> _showDocumentInfoDialog(String filename) async {
    final nameCtrl = TextEditingController(text: filename);
    final typeCtrl = TextEditingController();
    DateTime? expiryDate;

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Document Information'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Document Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: typeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Document Type (e.g., GST, PAN, License)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(
                  expiryDate != null
                      ? 'Expiry: ${DateFormat('dd/MM/yyyy').format(expiryDate!)}'
                      : 'No Expiry Date',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) {
                    expiryDate = picked;
                    (ctx as Element).markNeedsBuild();
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Document name is required')),
                );
                return;
              }
              Navigator.pop(ctx, {
                'name':   nameCtrl.text.trim(),
                'type':   typeCtrl.text.trim(),
                'expiry': expiryDate?.toIso8601String() ?? '',
              });
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':  return 'application/pdf';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png':  return 'image/png';
      case 'doc':
      case 'docx': return 'application/msword';
      case 'xls':
      case 'xlsx': return 'application/vnd.ms-excel';
      default:     return 'application/octet-stream';
    }
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Edit Client'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBasicInfoCard(),
              const SizedBox(height: 20),
              _buildContactInfoCard(),
              const SizedBox(height: 20),
              _buildLocationCard(),
              const SizedBox(height: 20),
              _buildBusinessInfoCard(),
              const SizedBox(height: 20),
              _buildExistingDocumentsCard(),
              const SizedBox(height: 20),
              _buildNewDocumentsCard(),
              const SizedBox(height: 30),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // CARDS
  // ─────────────────────────────────────────────────────────

  Widget _buildBasicInfoCard() {
    return _card(
      title: 'Basic Information',
      icon: Icons.business,
      child: Column(
        children: [
          _textField(
            controller: _nameCtrl,
            label: 'Company Name *',
            icon: Icons.business,
            validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _contactPersonCtrl,
            label: 'Contact Person',
            icon: Icons.person,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: InputDecoration(
              labelText: 'Status *',
              prefixIcon: const Icon(Icons.info),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'active'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfoCard() {
    return _card(
      title: 'Contact Information',
      icon: Icons.contact_phone,
      child: Column(
        children: [
          _textField(
            controller: _emailCtrl,
            label: 'Email *',
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v?.trim().isEmpty ?? true) return 'Required';
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v!)) {
                return 'Invalid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _phoneCtrl,
            label: 'Phone',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _addressCtrl,
            label: 'Address',
            icon: Icons.location_on,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return _card(
      title: 'Location Details',
      icon: Icons.map,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _countryCtrl,
                  label: 'Country',
                  icon: Icons.flag,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  controller: _stateCtrl,
                  label: 'State',
                  icon: Icons.location_city,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _cityCtrl,
                  label: 'City',
                  icon: Icons.location_on,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  controller: _areaCtrl,
                  label: 'Area',
                  icon: Icons.place,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessInfoCard() {
    return _card(
      title: 'Business Information',
      icon: Icons.business_center,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _departmentCtrl,
                  label: 'Department',
                  icon: Icons.apartment,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  controller: _branchCtrl,
                  label: 'Branch',
                  icon: Icons.account_tree,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _gstCtrl,
                  label: 'GST Number',
                  icon: Icons.receipt,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  controller: _panCtrl,
                  label: 'PAN Number',
                  icon: Icons.credit_card,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExistingDocumentsCard() {
    if (widget.client.documents.isEmpty) return const SizedBox.shrink();

    return _card(
      title: 'Existing Documents (${widget.client.documents.length})',
      icon: Icons.folder,
      child: Column(
        children: widget.client.documents.map((doc) {
          Color tagColor = Colors.blue;
          if (doc.isExpired) tagColor = Colors.red;
          else if (doc.expiresWithin30Days) tagColor = Colors.orange;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(_docIcon(doc.mimeType), color: Colors.blue[700], size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.documentName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        doc.originalName,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (doc.expiryDate != null)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tagColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            doc.isExpired ? 'EXPIRED' : 'Exp: ${doc.expiryDate}',
                            style: TextStyle(
                              fontSize: 10,
                              color: tagColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNewDocumentsCard() {
    return _card(
      title: 'Add New Documents',
      icon: Icons.upload_file,
      child: Column(
        children: [
          if (_newDocuments.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.cloud_upload, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text(
                    'No new documents added',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          else
            ..._newDocuments.asMap().entries.map((entry) {
              final idx = entry.key;
              final doc = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file, color: Colors.green[700], size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.documentName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            doc.filename,
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (doc.expiryDate?.isNotEmpty == true)
                            Text(
                              'Expires: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(doc.expiryDate!))}',
                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red, size: 20),
                      onPressed: () => setState(() => _newDocuments.removeAt(idx)),
                    ),
                  ],
                ),
              );
            }).toList(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDocuments,
            icon: const Icon(Icons.add),
            label: const Text('Add Documents'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              side: const BorderSide(color: Color(0xFF0D47A1)),
              foregroundColor: const Color(0xFF0D47A1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.grey[400]!),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _saveChanges,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(_isLoading ? 'Saving...' : 'Save Changes'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2),
        ),
      ),
    );
  }

  IconData _docIcon(String mime) {
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('image')) return Icons.image;
    if (mime.contains('word')) return Icons.description;
    if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart;
    return Icons.attach_file;
  }
}

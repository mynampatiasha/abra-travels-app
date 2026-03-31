// lib/features/client/organization_shift_config_screen.dart

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

// Import your organization model
import 'organization_model.dart';

class OrganizationShiftConfigScreen extends StatefulWidget {
  final OrganizationModel? organization;

  const OrganizationShiftConfigScreen({
    Key? key,
    this.organization,
  }) : super(key: key);

  @override
  State<OrganizationShiftConfigScreen> createState() =>
      _OrganizationShiftConfigScreenState();
}

class _OrganizationShiftConfigScreenState
    extends State<OrganizationShiftConfigScreen> {
  late List<ShiftDefinition> shifts;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    shifts = widget.organization?.shifts ?? [];
    if (shifts.isEmpty) {
      // Load default templates if no shifts exist
      shifts = ShiftTemplates.getDefaultShifts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Shift Configuration',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            onPressed: _showAddShiftDialog,
            tooltip: 'Add New Shift',
          ),
          IconButton(
            icon: const Icon(Icons.save, color: Colors.white),
            onPressed: _saveShiftConfiguration,
            tooltip: 'Save Configuration',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : shifts.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 20),
                    ...shifts.map((shift) => _buildShiftCard(shift)).toList(),
                    const SizedBox(height: 20),
                    _buildAddShiftButton(),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadTemplates,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Load Templates'),
        backgroundColor: const Color(0xFF8B5CF6),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.access_time,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shift Management',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${shifts.length} shifts configured',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configure your organization\'s shift timings. These will be available when creating rosters.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftCard(ShiftDefinition shift) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: shift.color?.withOpacity(0.3) ?? Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (shift.color ?? Colors.blue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getShiftIcon(shift.shiftType),
                      color: shift.color ?? Colors.blue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shift.shiftName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shift.getTimeRange(),
                          style: TextStyle(
                            fontSize: 14,
                            color: shift.color ?? Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: shift.isActive,
                    onChanged: (value) {
                      setState(() {
                        final index = shifts.indexOf(shift);
                        shifts[index] = shift.copyWith(isActive: value);
                      });
                    },
                    activeColor: const Color(0xFF10B981),
                  ),
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 12),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: Row(
                          children: [
                            Icon(Icons.content_copy, size: 20),
                            SizedBox(width: 12),
                            Text('Duplicate'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editShift(shift);
                          break;
                        case 'duplicate':
                          _duplicateShift(shift);
                          break;
                        case 'delete':
                          _deleteShift(shift);
                          break;
                      }
                    },
                  ),
                ],
              ),
              if (shift.description != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          shift.description!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoChip(
                    icon: Icons.schedule,
                    label: 'Duration',
                    value: _formatDuration(shift.getShiftDuration()),
                    color: const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                  if (shift.maxEmployees > 0)
                    _buildInfoChip(
                      icon: Icons.people,
                      label: 'Max',
                      value: shift.maxEmployees.toString(),
                      color: const Color(0xFF10B981),
                    ),
                  const SizedBox(width: 8),
                  if (shift.isOvernight())
                    _buildInfoChip(
                      icon: Icons.nightlight_round,
                      label: 'Overnight',
                      value: 'Yes',
                      color: const Color(0xFF8B5CF6),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: shift.allowedDays
                    .map((day) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (shift.color ?? Colors.blue).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: (shift.color ?? Colors.blue).withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            day,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: shift.color ?? Colors.blue,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddShiftButton() {
    return OutlinedButton.icon(
      onPressed: _showAddShiftDialog,
      icon: const Icon(Icons.add),
      label: const Text('Add New Shift'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2563EB),
        side: const BorderSide(color: Color(0xFF2563EB), width: 2),
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.access_time_outlined,
            size: 100,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 24),
          const Text(
            'No Shifts Configured',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first shift to get started',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddShiftDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Shift'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _loadTemplates,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Load Templates'),
          ),
        ],
      ),
    );
  }

  void _showAddShiftDialog() {
    _showShiftEditorDialog(null);
  }

  void _editShift(ShiftDefinition shift) {
    _showShiftEditorDialog(shift);
  }

  void _showShiftEditorDialog(ShiftDefinition? existingShift) {
    showDialog(
      context: context,
      builder: (context) => ShiftEditorDialog(
        shift: existingShift,
        onSave: (shift) {
          setState(() {
            if (existingShift != null) {
              final index = shifts.indexOf(existingShift);
              shifts[index] = shift;
            } else {
              shifts.add(shift);
            }
          });
        },
      ),
    );
  }

  void _duplicateShift(ShiftDefinition shift) {
    setState(() {
      shifts.add(shift.copyWith(
        id: const Uuid().v4(),
        shiftName: '${shift.shiftName} (Copy)',
      ));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shift duplicated successfully')),
    );
  }

  void _deleteShift(ShiftDefinition shift) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Shift'),
        content: Text('Are you sure you want to delete "${shift.shiftName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                shifts.remove(shift);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Shift deleted successfully')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _loadTemplates() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load Shift Templates'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This will add standard shift templates to your configuration.'),
            const SizedBox(height: 16),
            ...ShiftTemplates.getDefaultShifts().map((template) {
              return CheckboxListTile(
                title: Text(template.shiftName),
                subtitle: Text(template.getTimeRange()),
                value: true,
                onChanged: null,
              );
            }).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                final templates = ShiftTemplates.getDefaultShifts();
                for (final template in templates) {
                  if (!shifts.any((s) => s.shiftType == template.shiftType)) {
                    shifts.add(template);
                  }
                }
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Templates loaded successfully')),
              );
            },
            child: const Text('Load Templates'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveShiftConfiguration() async {
    setState(() => isLoading = true);

    try {
      // TODO: Save to backend
      // await organizationRepository.updateShifts(shifts);
      
      await Future.delayed(const Duration(seconds: 1)); // Simulate API call

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift configuration saved successfully'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context, shifts);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  IconData _getShiftIcon(String shiftType) {
    switch (shiftType.toLowerCase()) {
      case 'morning':
        return Icons.wb_sunny;
      case 'afternoon':
        return Icons.wb_twilight;
      case 'evening':
        return Icons.wb_twilight;
      case 'night':
        return Icons.nightlight_round;
      default:
        return Icons.access_time;
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }
}

// Shift Editor Dialog
class ShiftEditorDialog extends StatefulWidget {
  final ShiftDefinition? shift;
  final Function(ShiftDefinition) onSave;

  const ShiftEditorDialog({
    Key? key,
    this.shift,
    required this.onSave,
  }) : super(key: key);

  @override
  State<ShiftEditorDialog> createState() => _ShiftEditorDialogState();
}

class _ShiftEditorDialogState extends State<ShiftEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _maxEmployeesController;
  
  late String _selectedType;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late Color _selectedColor;
  late bool _isActive;
  late List<String> _selectedDays;

  final List<String> _shiftTypes = ['morning', 'afternoon', 'evening', 'night', 'custom'];
  final List<String> _allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final List<Color> _colorOptions = [
    const Color(0xFF2563EB),
    const Color(0xFF10B981),
    const Color(0xFFF59E0B),
    const Color(0xFFEF4444),
    const Color(0xFF8B5CF6),
    const Color(0xFF06B6D4),
    const Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.shift?.shiftName ?? '');
    _descriptionController = TextEditingController(text: widget.shift?.description ?? '');
    _maxEmployeesController = TextEditingController(
      text: widget.shift?.maxEmployees.toString() ?? '0',
    );
    
    _selectedType = widget.shift?.shiftType ?? 'custom';
    _startTime = widget.shift?.startTime ?? const TimeOfDay(hour: 9, minute: 0);
    _endTime = widget.shift?.endTime ?? const TimeOfDay(hour: 18, minute: 0);
    _selectedColor = widget.shift?.color ?? _colorOptions[0];
    _isActive = widget.shift?.isActive ?? true;
    _selectedDays = List.from(widget.shift?.allowedDays ?? _allDays);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _maxEmployeesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.shift == null ? 'Add New Shift' : 'Edit Shift'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Shift Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter shift name' : null,
              ),
              const SizedBox(height: 16),
              
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Shift Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: _shiftTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedType = value!);
                },
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: _buildTimeField(
                      'Start Time',
                      _startTime,
                      (time) => setState(() => _startTime = time),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTimeField(
                      'End Time',
                      _endTime,
                      (time) => setState(() => _endTime = time),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _maxEmployeesController,
                decoration: const InputDecoration(
                  labelText: 'Max Employees (0 = unlimited)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.people),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              
              const Text(
                'Shift Color',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _colorOptions.map((color) {
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColor == color
                              ? Colors.black
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: _selectedColor == color
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              
              const Text(
                'Active Days',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _allDays.map((day) {
                  final isSelected = _selectedDays.contains(day);
                  return FilterChip(
                    label: Text(day),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedDays.add(day);
                        } else {
                          _selectedDays.remove(day);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              
              SwitchListTile(
                title: const Text('Active'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveShift,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildTimeField(
    String label,
    TimeOfDay time,
    Function(TimeOfDay) onTimeSelected,
  ) {
    return InkWell(
      onTap: () async {
        final selectedTime = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (selectedTime != null) {
          onTimeSelected(selectedTime);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.access_time),
        ),
        child: Text(
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  void _saveShift() {
    if (_formKey.currentState?.validate() ?? false) {
      if (_selectedDays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one active day'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final shift = ShiftDefinition(
        id: widget.shift?.id ?? const Uuid().v4(),
        shiftName: _nameController.text,
        shiftType: _selectedType,
        startTime: _startTime,
        endTime: _endTime,
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        color: _selectedColor,
        isActive: _isActive,
        maxEmployees: int.tryParse(_maxEmployeesController.text) ?? 0,
        allowedDays: _selectedDays,
      );

      widget.onSave(shift);
      Navigator.pop(context);
    }
  }
}
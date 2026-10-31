import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/services/roster_service.dart';

/// Operations setting: how many minutes a driver needs between dropping the last
/// passenger of one trip and starting the next pickup (loading, parking, a short break).
/// Used when assigning vehicles: a driver who cannot make it in time is not offered.
Future<void> showDriverBufferDialog(BuildContext context, RosterService rosterService) async {
  final saved = await showDialog<int>(
    context: context,
    builder: (_) => _DriverBufferDialog(rosterService: rosterService),
  );
  if (saved != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Driver buffer set to $saved minutes - applies to new assignments'),
        backgroundColor: const Color(0xFF27AE60),
      ),
    );
  }
}

class _DriverBufferDialog extends StatefulWidget {
  final RosterService rosterService;

  const _DriverBufferDialog({required this.rosterService});

  @override
  State<_DriverBufferDialog> createState() => _DriverBufferDialogState();
}

class _DriverBufferDialogState extends State<_DriverBufferDialog> {
  static const List<int> _quickValues = [15, 20, 30, 40, 45, 60];

  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  int _min = 0;
  int _max = 120;
  int _default = 30;
  String? _updatedBy;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.rosterService.getAssignmentSettings();
      if (!mounted) return;
      setState(() {
        _min = (data['minMinutes'] as num?)?.toInt() ?? 0;
        _max = (data['maxMinutes'] as num?)?.toInt() ?? 120;
        _default = (data['defaultDriverBufferMinutes'] as num?)?.toInt() ?? 30;
        _controller.text = '${(data['driverBufferMinutes'] as num?)?.toInt() ?? _default}';
        _updatedBy = data['updatedBy']?.toString();
        _updatedAt = DateTime.tryParse(data['updatedAt']?.toString() ?? '')?.toLocal();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_controller.text.trim());
    if (minutes == null || minutes < _min || minutes > _max) {
      setState(() => _error = 'Enter a whole number between $_min and $_max');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.rosterService.updateDriverBufferMinutes(minutes);
      if (!mounted) return;
      Navigator.of(context).pop(minutes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.timer_outlined, color: Color(0xFF0D47A1)),
          SizedBox(width: 10),
          Expanded(child: Text('Driver buffer between trips')),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: _isLoading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Minutes the driver needs after dropping the last passenger, before the next pickup '
                    '(parking, short break, getting ready). It is added on top of the travel time to the next pickup.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _quickValues
                        .map((v) => ActionChip(
                              label: Text('$v min'),
                              onPressed: _isSaving
                                  ? null
                                  : () => setState(() {
                                        _controller.text = '$v';
                                        _error = null;
                                      }),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _controller,
                    enabled: !_isSaving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Buffer',
                      suffixText: 'minutes',
                      helperText: 'Whole number, $_min - $_max (standard: $_default)',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _updatedBy == null
                        ? 'Not changed yet - the standard value is in use.'
                        : 'Last changed by $_updatedBy'
                            '${_updatedAt != null ? ' on ${DateFormat('dd MMM yyyy, hh:mm a').format(_updatedAt!)}' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Applies to new assignments only. Trips that are already assigned are not changed.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_isLoading || _isSaving) ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

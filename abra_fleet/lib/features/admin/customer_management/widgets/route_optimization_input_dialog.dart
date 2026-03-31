// File: lib/features/admin/customer_management/widgets/route_optimization_input_dialog.dart
// Dialog for admin to input number of customers for route optimization
// ✅ ENHANCED: Better descriptions, visual improvements, pickup sequence explanation

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RouteOptimizationInputDialog extends StatefulWidget {
  final int maxCustomers;
  final Function(int, String) onOptimize; // (count, mode)

  const RouteOptimizationInputDialog({
    super.key,
    required this.maxCustomers,
    required this.onOptimize,
  });

  @override
  State<RouteOptimizationInputDialog> createState() => _RouteOptimizationInputDialogState();
}

class _RouteOptimizationInputDialogState extends State<RouteOptimizationInputDialog> {
  final _controller = TextEditingController();
  String? _errorMessage;
  String _selectedMode = 'auto'; // 'auto' or 'manual'

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleOptimize() {
    debugPrint('\n' + '🎯'*40);
    debugPrint('ROUTE OPTIMIZATION INPUT DIALOG: OPTIMIZE BUTTON CLICKED');
    debugPrint('🎯'*40);
    
    final text = _controller.text.trim();
    debugPrint('📝 User Input:');
    debugPrint('   - Text entered: "$text"');
    debugPrint('   - Selected mode: $_selectedMode');
    debugPrint('   - Max customers: ${widget.maxCustomers}');
    debugPrint('-'*80);
    
    if (text.isEmpty) {
      debugPrint('❌ Validation failed: Empty input');
      setState(() => _errorMessage = 'Please enter a number');
      return;
    }

    final number = int.tryParse(text);
    debugPrint('🔢 Parsed number: $number');
    
    if (number == null) {
      debugPrint('❌ Validation failed: Not a valid number');
      setState(() => _errorMessage = 'Please enter a valid number');
      return;
    }

    if (number < 1) {
      debugPrint('❌ Validation failed: Number less than 1');
      setState(() => _errorMessage = 'Number must be at least 1');
      return;
    }

    if (number > widget.maxCustomers) {
      debugPrint('❌ Validation failed: Number exceeds max customers ($number > ${widget.maxCustomers})');
      setState(() => _errorMessage = 'Maximum ${widget.maxCustomers} customers available');
      return;
    }

    debugPrint('✅ Validation passed!');
    debugPrint('📤 Closing dialog and calling onOptimize callback');
    debugPrint('   - Customer count: $number');
    debugPrint('   - Mode: $_selectedMode');
    debugPrint('🎯'*40 + '\n');
    
    Navigator.of(context).pop();
    widget.onOptimize(number, _selectedMode);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.route, color: Colors.green.shade700, size: 24),
          ),
          const SizedBox(width: 12),
          const Text('Route Optimization'),
        ],
      ),
      content: SingleChildScrollView( // ✅ FIX: Added for long content
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How many customers would you like to optimize for?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            
            // Mode Selection
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'auto',
                    groupValue: _selectedMode,
                    onChanged: (value) => setState(() => _selectedMode = value!),
                    title: Row(
                      children: [
                        const Text(
                          'Auto Mode',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'RECOMMENDED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: const Text(
                      'AI finds best vehicle and optimizes pickup sequence automatically',
                      style: TextStyle(fontSize: 13),
                    ),
                    secondary: Icon(Icons.auto_awesome, color: Colors.green.shade700, size: 28),
                  ),
                  Divider(height: 1, color: Colors.grey.shade300),
                  RadioListTile<String>(
                    value: 'manual',
                    groupValue: _selectedMode,
                    onChanged: (value) => setState(() => _selectedMode = value!),
                    title: const Text(
                      'Manual Mode',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'You select the vehicle and driver manually',
                      style: TextStyle(fontSize: 13),
                    ),
                    secondary: Icon(Icons.touch_app, color: Colors.blue.shade700, size: 28),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Number Input
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Number of Customers',
                hintText: 'e.g., 3',
                prefixIcon: const Icon(Icons.people),
                suffixText: '/ ${widget.maxCustomers}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                errorText: _errorMessage,
                helperText: 'Enter a number between 1 and ${widget.maxCustomers}',
                helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              onChanged: (value) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              onSubmitted: (_) => _handleOptimize(),
            ),
            
            const SizedBox(height: 16),
            
            // ✅ ENHANCED: More detailed mode explanation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _selectedMode == 'auto' ? Colors.green.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _selectedMode == 'auto' ? Colors.green.shade200 : Colors.blue.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _selectedMode == 'auto' ? Icons.auto_awesome : Icons.info_outline,
                        color: _selectedMode == 'auto' ? Colors.green.shade700 : Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedMode == 'auto' ? 'How Auto Mode Works:' : 'How Manual Mode Works:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _selectedMode == 'auto' ? Colors.green.shade900 : Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedMode == 'auto'
                        ? '1. AI finds the best customer group from the same company\n'
                          '2. Selects optimal vehicle based on capacity & proximity\n'
                          '3. Optimizes pickup sequence (furthest → nearest)\n'
                          '4. Calculates timing with 20-minute ready-by buffer\n'
                          '5. Sends notifications with driver name & phone'
                        : '1. AI groups customers from the same company\n'
                          '2. Shows you all compatible vehicles\n'
                          '3. You choose which vehicle/driver to use\n'
                          '4. Route is optimized (furthest → nearest)\n'
                          '5. Seat capacity is automatically tracked',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: _selectedMode == 'auto' ? Colors.green.shade900 : Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ),
            
            // ✅ NEW: Pickup Sequence Explanation
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.route, size: 18, color: Colors.purple.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📍 Pickup Sequence Logic',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Furthest customer from office is picked FIRST, nearest customer picked LAST. This ensures efficient routing.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.purple.shade800,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _handleOptimize,
          icon: Icon(
            _selectedMode == 'auto' ? Icons.auto_awesome : Icons.touch_app,
            size: 18,
          ),
          label: Text(_selectedMode == 'auto' ? 'Auto Optimize' : 'Select Manually'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedMode == 'auto' ? Colors.green.shade700 : Colors.blue.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }
}
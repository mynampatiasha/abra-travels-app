// lib/features/admin/admin_report_generator.dart
// ============================================================================
// ADMIN REPORT GENERATOR - CHUNK 2
// ============================================================================
// ✅ Generates PDF with all trip details automatically
// ✅ Includes: Trip info, vehicle, driver, customers, stops, distances, feedback
// ✅ Works on both web (share/download) and mobile (print/share)
// ✅ Full summary statistics for the filtered result set
// ============================================================================

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AdminReportGenerator extends StatefulWidget {
  final Map<String, dynamic> reportData;
  final String filterSummary;

  const AdminReportGenerator({
    super.key,
    required this.reportData,
    required this.filterSummary,
  });

  @override
  State<AdminReportGenerator> createState() => _AdminReportGeneratorState();
}

class _AdminReportGeneratorState extends State<AdminReportGenerator> {
  bool _isGenerating = false;
  bool _isGenerated = false;
  String _statusMessage = '';
  pw.Document? _pdfDoc;

  @override
  void initState() {
    super.initState();
    // Auto-generate on open
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateAndDownload());
  }

  Future<void> _generateAndDownload() async {
    setState(() {
      _isGenerating = true;
      _statusMessage = 'Building PDF report...';
    });

    try {
      final pdf = await _buildPdf();
      _pdfDoc = pdf;

      setState(() => _statusMessage = 'Saving report...');
      final bytes = await pdf.save();

      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'trip_report_$timestamp.pdf';

      if (kIsWeb) {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
      }

      setState(() {
        _isGenerating = false;
        _isGenerated = true;
        _statusMessage = 'Report generated successfully!';
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _statusMessage = 'Error: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<pw.Document> _buildPdf() async {
    final pdf = pw.Document();
    final data = widget.reportData;
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final trips = (data['trips'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final generatedAt = DateTime.now();

    // ── Colour palette ────────────────────────────────────────────────────
    const headerBlue = PdfColor.fromInt(0xFF0D47A1);
    const lightBlue = PdfColor.fromInt(0xFFE3EAF5);
    const greenColor = PdfColor.fromInt(0xFF2E7D32);
    const lightGreen = PdfColor.fromInt(0xFFE8F5E9);
    const redColor = PdfColor.fromInt(0xFFC62828);
    const greyText = PdfColor.fromInt(0xFF555555);
    const tableRowAlt = PdfColor.fromInt(0xFFF5F7FA);

    // ── Cover / Summary page ──────────────────────────────────────────────
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: (ctx) => pw.Column(children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('TRIP MANAGEMENT REPORT',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: headerBlue)),
              pw.Text('Filter: ${widget.filterSummary}',
                  style: pw.TextStyle(fontSize: 10, color: greyText)),
              pw.Text('Generated: ${DateFormat('EEEE, MMM dd yyyy – HH:mm').format(generatedAt)}',
                  style: pw.TextStyle(fontSize: 9, color: greyText)),
            ]),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: headerBlue, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Text('ABRA FLEET',
                  style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(color: headerBlue, thickness: 1.5),
      ]),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Abra Fleet – Trip Report', style: pw.TextStyle(fontSize: 8, color: greyText)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 8, color: greyText)),
        ],
      ),
      build: (ctx) => [
        pw.SizedBox(height: 10),

        // ── Summary statistics grid ──────────────────────────────────────
        pw.Text('SUMMARY STATISTICS',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: headerBlue)),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: lightBlue, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfStat('Total Trips', (summary['total'] ?? trips.length).toString(), headerBlue),
              _pdfStat('Ongoing', (summary['ongoing'] ?? 0).toString(), greenColor),
              _pdfStat('Scheduled', (summary['scheduled'] ?? 0).toString(), PdfColor.fromInt(0xFF1565C0)),
              _pdfStat('Completed', (summary['completed'] ?? 0).toString(), greyText),
              _pdfStat('Cancelled', (summary['cancelled'] ?? 0).toString(), redColor),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: lightGreen, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfStat('Vehicles', (summary['totalVehicles'] ?? 0).toString(), greenColor),
              _pdfStat('Drivers', (summary['totalDrivers'] ?? 0).toString(), greenColor),
              _pdfStat('Customers', (summary['totalCustomers'] ?? 0).toString(), greenColor),
              _pdfStat('Delayed', (summary['delayed'] ?? 0).toString(), redColor),
              _pdfStat('Total km', (summary['totalDistance'] ?? 0).toStringAsFixed(1), PdfColor.fromInt(0xFF6A1B9A)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),

        // ── Trip list table ───────────────────────────────────────────────
        pw.Text('TRIP DETAILS',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: headerBlue)),
        pw.SizedBox(height: 8),
        _buildTripsTable(trips, headerBlue, tableRowAlt, greyText),

        pw.SizedBox(height: 24),

        // ── Per-trip detail sections ──────────────────────────────────────
        ...trips.asMap().entries.map((entry) {
          final idx = entry.key;
          final trip = entry.value;
          return _buildTripDetailSection(trip, idx + 1, headerBlue, lightBlue, tableRowAlt, greyText, greenColor, redColor);
        }),
      ],
    ));

    return pdf;
  }

  pw.Widget _pdfStat(String label, String value, PdfColor color) {
    return pw.Column(children: [
      pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
      pw.SizedBox(height: 2),
      pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF555555))),
    ]);
  }

  pw.Widget _buildTripsTable(
      List<Map<String, dynamic>> trips,
      PdfColor headerBlue,
      PdfColor tableRowAlt,
      PdfColor greyText) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(28),
        1: const pw.FixedColumnWidth(65),
        2: const pw.FlexColumnWidth(1.2),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FixedColumnWidth(50),
        5: const pw.FixedColumnWidth(50),
        6: const pw.FixedColumnWidth(42),
        7: const pw.FixedColumnWidth(42),
        8: const pw.FixedColumnWidth(48),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBlue),
          children: [
            _tCell('#', header: true),
            _tCell('Trip No.', header: true),
            _tCell('Vehicle', header: true),
            _tCell('Driver', header: true),
            _tCell('Date', header: true),
            _tCell('Time', header: true),
            _tCell('Stops', header: true),
            _tCell('Dist.', header: true),
            _tCell('Status', header: true),
          ],
        ),
        ...trips.asMap().entries.map((e) {
          final i = e.key;
          final t = e.value;
          final isAlt = i % 2 == 1;
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isAlt ? tableRowAlt : PdfColors.white),
            children: [
              _tCell('${i + 1}'),
              _tCell(t['tripNumber']?.toString() ?? 'N/A'),
              _tCell(t['vehicleNumber']?.toString() ?? 'Unknown'),
              _tCell(t['driverName']?.toString() ?? 'Unknown'),
              _tCell(_formatDate(t['scheduledDate']?.toString())),
              _tCell('${t['startTime'] ?? ''}–${t['endTime'] ?? ''}'),
              _tCell('${t['completedStops'] ?? 0}/${t['totalStops'] ?? 0}'),
              _tCell('${(t['totalDistance'] ?? 0).toStringAsFixed(1)}km'),
              _tCell(_statusLabel(t['status']?.toString())),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildTripDetailSection(
      Map<String, dynamic> trip,
      int idx,
      PdfColor headerBlue,
      PdfColor lightBlue,
      PdfColor tableRowAlt,
      PdfColor greyText,
      PdfColor greenColor,
      PdfColor redColor) {
    final stops = (trip['stops'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final vehicle = trip['vehicle'] as Map<String, dynamic>? ?? {};
    final driver = trip['driver'] as Map<String, dynamic>? ?? {};
    final metrics = trip['metrics'] as Map<String, dynamic>? ?? {};

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      // ── Section header ─────────────────────────────────────────────────
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: headerBlue,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('$idx. ${trip['tripNumber'] ?? 'N/A'}',
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.Text(_statusLabel(trip['status']?.toString()),
                style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
      pw.SizedBox(height: 6),

      // ── Vehicle + Driver side by side ──────────────────────────────────
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: _pdfInfoBox('VEHICLE', [
            ['Number', trip['vehicleNumber']?.toString() ?? vehicle['vehicleNumber']?.toString() ?? 'N/A'],
            ['Name', trip['vehicleName']?.toString() ?? vehicle['vehicleName']?.toString() ?? 'N/A'],
            ['Make/Model', '${vehicle['manufacturer'] ?? 'N/A'} ${vehicle['model'] ?? ''}'.trim()],
            ['Capacity', vehicle['capacity']?.toString() ?? 'N/A'],
            ['Fuel', vehicle['fuelType']?.toString() ?? 'N/A'],
          ], lightBlue, greyText),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _pdfInfoBox('DRIVER', [
            ['Name', trip['driverName']?.toString() ?? driver['name']?.toString() ?? 'N/A'],
            ['Phone', trip['driverPhone']?.toString() ?? driver['phone']?.toString() ?? 'N/A'],
            ['Email', trip['driverEmail']?.toString() ?? driver['email']?.toString() ?? 'N/A'],
            ['License', driver['licenseNumber']?.toString() ?? 'N/A'],
          ], lightBlue, greyText),
        ),
      ]),
      pw.SizedBox(height: 6),

      // ── Trip info ──────────────────────────────────────────────────────
      _pdfInfoBox('TRIP DETAILS', [
        ['Scheduled Date', _formatDate(trip['scheduledDate']?.toString())],
        ['Scheduled Time', '${trip['startTime'] ?? 'N/A'} – ${trip['endTime'] ?? 'N/A'}'],
        if (trip['actualStartTime'] != null) ['Actual Start', _formatDateTime(trip['actualStartTime']?.toString())],
        if (trip['actualEndTime'] != null) ['Actual End', _formatDateTime(trip['actualEndTime']?.toString())],
        ['Total Stops', '${trip['totalStops'] ?? 0}'],
        ['Completed Stops', '${trip['completedStops'] ?? 0}'],
        ['Total Distance', '${(trip['totalDistance'] ?? 0).toStringAsFixed(2)} km'],
        if (trip['actualDistance'] != null && (trip['actualDistance'] as num) > 0)
          ['Actual Distance', '${(trip['actualDistance'] as num).toStringAsFixed(2)} km'],
        if (trip['startOdometer'] != null) ['Start Odometer', trip['startOdometer'].toString()],
        if (trip['endOdometer'] != null) ['End Odometer', trip['endOdometer'].toString()],
        ['On-Time Stops', (metrics['onTimeStops'] ?? 0).toString()],
        ['Delayed Stops', (metrics['delayedStops'] ?? 0).toString()],
        if ((metrics['averageDelay'] ?? 0) > 0) ['Avg Delay', '${metrics['averageDelay']} min'],
      ], PdfColor.fromInt(0xFFF5F7FA), greyText),
      pw.SizedBox(height: 6),

      // ── Stops table ────────────────────────────────────────────────────
      if (stops.isNotEmpty) ...[
        pw.Text('ROUTE STOPS (${stops.length})',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: headerBlue)),
        pw.SizedBox(height: 4),
        _buildStopsTable(stops, headerBlue, tableRowAlt, greyText),
        pw.SizedBox(height: 6),
      ],

      // ── Customer feedback ──────────────────────────────────────────────
      _buildFeedbackSection(trip, headerBlue, greyText, greenColor),

      pw.SizedBox(height: 16),
      pw.Divider(color: PdfColor.fromInt(0xFFCCCCCC)),
      pw.SizedBox(height: 10),
    ]);
  }

  pw.Widget _pdfInfoBox(String title, List<List<String>> rows, PdfColor bg, PdfColor greyText) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0D47A1))),
        pw.SizedBox(height: 5),
        ...rows.map((row) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(children: [
                pw.SizedBox(
                  width: 90,
                  child: pw.Text('${row[0]}:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Expanded(child: pw.Text(row[1], style: pw.TextStyle(fontSize: 8, color: greyText))),
              ]),
            )),
      ]),
    );
  }

  pw.Widget _buildStopsTable(
      List<Map<String, dynamic>> stops,
      PdfColor headerBlue,
      PdfColor tableRowAlt,
      PdfColor greyText) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FixedColumnWidth(42),
        2: const pw.FlexColumnWidth(1.3),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FixedColumnWidth(50),
        5: const pw.FixedColumnWidth(50),
        6: const pw.FixedColumnWidth(45),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBlue),
          children: [
            _tCell('Seq', header: true, small: true),
            _tCell('Type', header: true, small: true),
            _tCell('Customer', header: true, small: true),
            _tCell('Address', header: true, small: true),
            _tCell('Est.Time', header: true, small: true),
            _tCell('Actual', header: true, small: true),
            _tCell('Status', header: true, small: true),
          ],
        ),
        ...stops.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          final customer = s['customer'] as Map<String, dynamic>? ?? {};
          final location = s['location'] as Map<String, dynamic>? ?? {};
          final isAlt = i % 2 == 1;

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isAlt ? tableRowAlt : PdfColors.white),
            children: [
              _tCell(s['sequence']?.toString() ?? '$i', small: true),
              _tCell((s['type']?.toString() ?? '').toUpperCase(), small: true),
              _tCell(customer['name']?.toString() ?? s['customerName']?.toString() ?? 'Drop', small: true),
              _tCell(location['address']?.toString() ?? s['address']?.toString() ?? 'N/A', small: true),
              _tCell(s['estimatedTime']?.toString() ?? 'N/A', small: true),
              _tCell(s['arrivedAt'] != null ? _formatDateTime(s['arrivedAt'].toString()) : '—', small: true),
              _tCell(_statusLabel(s['status']?.toString()), small: true),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildFeedbackSection(
      Map<String, dynamic> trip,
      PdfColor headerBlue,
      PdfColor greyText,
      PdfColor greenColor) {
    final feedbackList = (trip['customerFeedback'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    if (feedbackList.isEmpty) return pw.SizedBox.shrink();

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('CUSTOMER FEEDBACK (${feedbackList.length})',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: headerBlue)),
      pw.SizedBox(height: 4),
      ...feedbackList.map((fb) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 5),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3))),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(fb['customerName']?.toString() ?? 'Anonymous',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    if (fb['feedback'] != null && fb['feedback'].toString().isNotEmpty)
                      pw.Text(fb['feedback'].toString(), style: pw.TextStyle(fontSize: 8, color: greyText)),
                  ]),
                ),
                pw.SizedBox(width: 10),
                pw.Text('${fb['rating'] ?? 0}/5 ★', style: pw.TextStyle(fontSize: 10, color: greenColor, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          )),
    ]);
  }

  // ─── Table cell helper ────────────────────────────────────────────────────

  pw.Widget _tCell(String text, {bool header = false, bool small = false}) {
    return pw.Padding(
      padding: pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: small ? 7.5 : (header ? 8.5 : 9),
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header ? PdfColors.white : PdfColors.black,
        ),
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  // ─── Format helpers ───────────────────────────────────────────────────────

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      return DateFormat('MMM dd, yyyy').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  String _statusLabel(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'started': case 'in_progress': return 'ONGOING';
      case 'assigned': return 'SCHEDULED';
      case 'completed': return 'COMPLETED';
      case 'cancelled': return 'CANCELLED';
      default: return (status ?? 'N/A').toUpperCase();
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        title: const Text('Trip Report', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_isGenerated)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Download Again',
              onPressed: _generateAndDownload,
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isGenerating) ...[
                const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.green)),
                const SizedBox(height: 24),
                Text(_statusMessage, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text('Please wait while your report is being prepared...',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ] else if (_isGenerated) ...[
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 72),
                const SizedBox(height: 20),
                const Text('Report Generated!',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_statusMessage, style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 24),
                _buildReportSummaryCard(),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _generateAndDownload,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Download Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Trips'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ] else ...[
                const Icon(Icons.error_outline, color: Colors.red, size: 72),
                const SizedBox(height: 20),
                const Text('Generation Failed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_statusMessage, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _generateAndDownload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportSummaryCard() {
    final summary = widget.reportData['summary'] as Map<String, dynamic>? ?? {};
    final trips = widget.reportData['trips'] as List<dynamic>? ?? [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Report Summary', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _summaryChip('📋 ${trips.length} Trips'),
          _summaryChip('🚗 ${summary['totalVehicles'] ?? 0} Vehicles'),
          _summaryChip('👤 ${summary['totalDrivers'] ?? 0} Drivers'),
          _summaryChip('👥 ${summary['totalCustomers'] ?? 0} Customers'),
          _summaryChip('✅ ${summary['completed'] ?? 0} Completed'),
          _summaryChip('📍 ${(summary['totalDistance'] ?? 0).toStringAsFixed(1)} km'),
        ]),
        const SizedBox(height: 10),
        Text('Filter: ${widget.filterSummary}',
            style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
      ]),
    );
  }

  Widget _summaryChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.shade200)),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}
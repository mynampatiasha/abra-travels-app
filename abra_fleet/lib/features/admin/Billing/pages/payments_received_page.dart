// ============================================================================
// PAYMENTS RECEIVED PAGE — mirrors payment_made_list_page.dart exactly
// ✅ Single-row top bar: dropdown + search + date filters + refresh + view process + New + Export
// ✅ Responsive: desktop single row, tablet 2 rows, mobile stacked
// ✅ DataTable with dark header + horizontal cursor-based scrolling
// ✅ View Process → assets/payment_received.png in LARGE dialog
// ✅ All existing functionality preserved
// ============================================================================
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/payment_service.dart';
import '../app_top_bar.dart';
import 'new_payment_page.dart';

class PaymentsReceivedPage extends StatefulWidget {
  const PaymentsReceivedPage({Key? key}) : super(key: key);

  @override
  State<PaymentsReceivedPage> createState() => _PaymentsReceivedPageState();
}

class _PaymentsReceivedPageState extends State<PaymentsReceivedPage> {
  // ── constants ──────────────────────────────────────────────────────────────
  static const _primary = Color(0xFF3498DB);
  static const _dark    = Color(0xFF2C3E50);

  static const _filterOptions = ['All Payments', 'Draft', 'Paid', 'Void'];

  // ── data ───────────────────────────────────────────────────────────────────
  String selectedFilter = 'All Payments';
  List<Map<String, dynamic>> payments         = [];
  List<Map<String, dynamic>> filteredPayments = [];
  bool isLoading = true;

  // ── date range ─────────────────────────────────────────────────────────────
  DateTime? fromDate;
  DateTime? toDate;

  // ── search ─────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String searchQuery = '';

  // ── scroll controllers ─────────────────────────────────────────────────────
  final _hScrollCtrl = ScrollController();
  final _vScrollCtrl = ScrollController();

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadPayments();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hScrollCtrl.dispose();
    _vScrollCtrl.dispose();
    super.dispose();
  }

  // ── data loading ───────────────────────────────────────────────────────────
  void _onSearchChanged() {
    setState(() {
      searchQuery = _searchCtrl.text.toLowerCase();
      _applyFilters();
    });
  }

  Future<void> _loadPayments() async {
    setState(() => isLoading = true);
    try {
      final result = await PaymentService.getPaymentsReceived(
        filter: selectedFilter == 'All Payments' ? null : selectedFilter,
      );
      setState(() {
        payments = result;
        _applyFilters();
        isLoading = false;
      });
      _snack('Loaded ${payments.length} payments', Colors.green);
    } catch (e) {
      setState(() => isLoading = false);
      _snack('Error loading payments: $e', Colors.red);
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> result = List.from(payments);
    if (fromDate != null || toDate != null) {
      result = result.where((p) {
        try {
          final parts = (p['date'] ?? '').split('/');
          if (parts.length != 3) return false;
          final d = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          if (fromDate != null && d.isBefore(fromDate!)) return false;
          if (toDate   != null && d.isAfter(toDate!))   return false;
          return true;
        } catch (_) { return false; }
      }).toList();
    }
    if (searchQuery.isNotEmpty) {
      result = result.where((p) {
        return (p['paymentNumber']   ?? '').toString().toLowerCase().contains(searchQuery) ||
               (p['customerName']   ?? '').toString().toLowerCase().contains(searchQuery) ||
               (p['referenceNumber']?? '').toString().toLowerCase().contains(searchQuery) ||
               (p['invoiceNumber']  ?? '').toString().toLowerCase().contains(searchQuery) ||
               (p['mode']           ?? '').toString().toLowerCase().contains(searchQuery) ||
               (p['amount']         ?? '').toString().toLowerCase().contains(searchQuery);
      }).toList();
    }
    setState(() => filteredPayments = result);
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color,
        behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  // ── date pickers ───────────────────────────────────────────────────────────
  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() { fromDate = picked; _applyFilters(); });
  }

  Future<void> _selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() { toDate = picked; _applyFilters(); });
  }

  void _clearDateFilters() => setState(() { fromDate = null; toDate = null; _applyFilters(); });
  bool get _hasDateFilters => fromDate != null || toDate != null;

  // ── export ─────────────────────────────────────────────────────────────────
  Future<void> _exportToExcel() async {
    try {
      if (payments.isEmpty) { _snack('No payments to export', Colors.orange); return; }
      _snack('Preparing Excel export...', Colors.blueGrey);
      List<Map<String, dynamic>> fullPayments = [];
      for (var p in payments) {
        try {
          final full = await PaymentService.getPayment(p['id'].toString());
          fullPayments.add(full);
        } catch (_) { fullPayments.add(p); }
      }
      final rows = <List<dynamic>>[
        ['Payment Date','Payment Number','Reference Number','Customer Name','Invoice Number',
         'Payment Mode','Amount Received','Bank Charges','Net Amount','Deposit To',
         'Tax Deduction','Status','Has Proofs','Proofs Count','Notes','Created At','Updated At'],
        ...fullPayments.map((p) {
          final amount     = (p['amountReceived'] ?? p['amount']  ?? 0.0).toDouble();
          final bankCharge = (p['bankCharges']    ?? 0.0).toDouble();
          final net        = (p['netAmount']       ?? (amount - bankCharge)).toDouble();
          return [
            p['paymentDate'] ?? p['date'] ?? '',
            p['paymentNumber'] ?? '',
            p['reference'] ?? p['referenceNumber'] ?? '',
            p['customerName'] ?? '',
            p['invoiceNumber'] ?? '',
            p['paymentMode'] ?? p['mode'] ?? 'N/A',
            amount.toStringAsFixed(2),
            bankCharge.toStringAsFixed(2),
            net.toStringAsFixed(2),
            p['depositTo'] ?? 'N/A',
            p['taxDeduction'] ?? 'No Tax deducted',
            p['status'] ?? 'Paid',
            (p['paymentProofs'] != null && (p['paymentProofs'] as List).isNotEmpty) || p['hasProofs'] == true ? 'Yes' : 'No',
            p['paymentProofs'] != null ? (p['paymentProofs'] as List).length.toString() : (p['proofsCount'] ?? 0).toString(),
            p['notes'] ?? '',
            p['createdAt'] ?? '',
            p['updatedAt'] ?? '',
          ];
        }),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'payments_received');
      _snack('✅ Exported ${payments.length} payments', Colors.green);
    } catch (e) {
      _snack('Export failed: $e', Colors.red);
    }
  }

  // ── view / delete ──────────────────────────────────────────────────────────
  void _viewPaymentDetails(Map<String, dynamic> payment) {
    showDialog(context: context, builder: (_) => PaymentDetailsDialog(payment: payment));
  }

  Future<void> _viewPaymentProofs(Map<String, dynamic> payment) async {
    try {
      final proofs = await PaymentService.getPaymentProofs(payment['id']);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Payment Proofs - #${payment['paymentNumber']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: proofs.length,
              itemBuilder: (_, i) {
                final proof = proofs[i];
                return ListTile(
                  leading: Icon(
                    proof.fileType.contains('pdf') ? Icons.picture_as_pdf : Icons.image,
                    color: _primary, size: 32,
                  ),
                  title: Text(proof.filename),
                  subtitle: Text('${(proof.fileSize / 1024).toStringAsFixed(1)} KB',
                    style: TextStyle(color: Colors.grey[600])),
                  trailing: IconButton(
                    icon: const Icon(Icons.download, color: _primary),
                    onPressed: () async {
                      final url = await PaymentService.downloadPaymentProof(payment['id'], i.toString());
                      _snack('Download: $url', Colors.blue);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (e) { _snack('Failed to load proofs: $e', Colors.red); }
  }

  Future<void> _deletePayment(Map<String, dynamic> payment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Payment'),
        content: Text('Are you sure you want to delete payment #${payment['paymentNumber']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await PaymentService.deletePayment(payment['id']);
        _snack('Payment deleted successfully', Colors.green);
        _loadPayments();
      } catch (e) { _snack('Failed to delete: $e', Colors.red); }
    }
  }

  void _navigateToNewPayment() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const NewPaymentPage()))
        .then((_) => _loadPayments());
  }

  // ── View Process Dialog ─────────────────────────────────────────────────────
  void _showProcessDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      builder: (ctx) {
        final screenSize = MediaQuery.of(context).size;
        final dialogW = (screenSize.width * 0.88).clamp(320.0, 1000.0);
        final dialogH = screenSize.height * 0.85;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: dialogW,
              height: dialogH,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12))],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: _primary,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.account_tree_outlined, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Payments Received — Process Flow', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
                      InkWell(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, color: Colors.white, size: 20)),
                    ]),
                  ),
                  // Image fills remaining space
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
                      child: Image.asset(
                        'assets/payment_received.png',
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _fallbackFlowDiagram(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackFlowDiagram() {
    final steps = [
      {'icon': Icons.drafts_outlined,  'label': 'DRAFT',    'color': Colors.grey},
      {'icon': Icons.check_circle,     'label': 'PAID',     'color': Colors.green},
      {'icon': Icons.cancel_outlined,  'label': 'VOID',     'color': Colors.red},
    ];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 16,
          children: steps.expand((s) => [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: (s['color'] as Color).withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: s['color'] as Color, width: 2)),
                child: Column(children: [Icon(s['icon'] as IconData, color: s['color'] as Color, size: 28), const SizedBox(height: 6),
                  Text(s['label'] as String, style: TextStyle(color: s['color'] as Color, fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)])),
            ]),
            if (s != steps.last) Padding(padding: const EdgeInsets.only(top: 20), child: Icon(Icons.arrow_forward_rounded, color: Colors.grey.shade400)),
          ]).toList(),
        ),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
          child: const Text('Draft → Paid → Void', textAlign: TextAlign.center, style: TextStyle(fontSize: 15))),
      ]),
    );
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Payments Received'),
      backgroundColor: const Color(0xFFF4F6F9),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            _buildStatsCards(),
            _buildTableSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth < 700)  return _topBarMobile();
        if (c.maxWidth < 1100) return _topBarTablet();
        return _topBarDesktop();
      }),
    );
  }

  // ─ Desktop: ALL controls in ONE row ────────────────────────────────────────
  Widget _topBarDesktop() => Row(children: [
    _statusDropdown(),
    const SizedBox(width: 12),
    _searchField(width: 240),
    const SizedBox(width: 8),
    _dateTile(fromDate, 'From', _selectFromDate),
    const SizedBox(width: 6),
    _dateTile(toDate, 'To', _selectToDate),
    if (_hasDateFilters) ...[
      const SizedBox(width: 4),
      _clearDateBtn(),
    ],
    const Spacer(),
    _iconBtn(Icons.refresh_rounded, isLoading ? null : _loadPayments, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'View Process', color: _primary),
    const SizedBox(width: 12),
    _actionBtn('New', Icons.add_rounded, _primary, _navigateToNewPayment),
    const SizedBox(width: 8),
    _actionBtn('Export Excel', Icons.download_rounded, const Color(0xFF27AE60), _exportToExcel),
  ]);

  // ─ Tablet: row 1 = dropdown + search + dates + refresh + process; row 2 = buttons ─
  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      _searchField(width: 180),
      const SizedBox(width: 6),
      _dateTile(fromDate, 'From', _selectFromDate),
      const SizedBox(width: 4),
      _dateTile(toDate, 'To', _selectToDate),
      if (_hasDateFilters) ...[const SizedBox(width: 4), _clearDateBtn()],
      const Spacer(),
      _iconBtn(Icons.refresh_rounded, isLoading ? null : _loadPayments, tooltip: 'Refresh'),
      const SizedBox(width: 4),
      _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'View Process', color: _primary),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New', Icons.add_rounded, _primary, _navigateToNewPayment),
      const SizedBox(width: 8),
      _actionBtn('Export Excel', Icons.download_rounded, const Color(0xFF27AE60), _exportToExcel),
    ]),
  ]);

  // ─ Mobile: stacked ──────────────────────────────────────────────────────────
  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: _statusDropdown()),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _primary, _navigateToNewPayment),
    ]),
    const SizedBox(height: 10),
    _searchField(width: double.infinity),
    const SizedBox(height: 10),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _dateTile(fromDate, 'From', _selectFromDate),
        const SizedBox(width: 6),
        _dateTile(toDate, 'To', _selectToDate),
        if (_hasDateFilters) ...[const SizedBox(width: 4), _clearDateBtn()],
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, isLoading ? null : _loadPayments, tooltip: 'Refresh'),
        const SizedBox(width: 6),
        _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'Process', color: _primary),
        const SizedBox(width: 6),
        _compactBtn('Export', const Color(0xFF27AE60), _exportToExcel),
      ]),
    ),
  ]);

  // ─ Shared top bar widgets ───────────────────────────────────────────────────
  Widget _statusDropdown() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selectedFilter,
        isDense: true,
        items: _filterOptions.map((f) => DropdownMenuItem(value: f,
          child: Text(f, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))).toList(),
        onChanged: (v) { if (v != null) { setState(() => selectedFilter = v); _loadPayments(); } },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final tf = TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Search payment#, customer, ref…',
        hintStyle: const TextStyle(fontSize: 15),
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: searchQuery.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); setState(() { searchQuery = ''; _applyFilters(); }); })
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
      ),
      onChanged: (v) { setState(() { searchQuery = v.toLowerCase(); _applyFilters(); }); },
    );
    if (width == double.infinity) return tf;
    return SizedBox(width: width, child: tf);
  }

  Widget _dateTile(DateTime? date, String hint, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: date != null ? _primary.withOpacity(0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: date != null ? _primary : Colors.grey.shade300),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.calendar_today, size: 14, color: date != null ? _primary : Colors.grey[600]),
        const SizedBox(width: 6),
        Text(
          date != null ? DateFormat('dd/MM/yy').format(date) : hint,
          style: TextStyle(fontSize: 13, fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
            color: date != null ? _primary : Colors.grey[700]),
        ),
      ]),
    ),
  );

  Widget _clearDateBtn() => Tooltip(
    message: 'Clear Date Filters',
    child: IconButton(
      icon: const Icon(Icons.clear, color: Colors.red, size: 16),
      onPressed: _clearDateFilters,
      style: IconButton.styleFrom(backgroundColor: Colors.red[50], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.all(8)),
    ),
  );

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String? tooltip, Color color = const Color(0xFF7F8C8D)}) =>
    Tooltip(
      message: tooltip ?? '',
      child: IconButton(
        icon: Icon(icon, size: 20, color: onTap == null ? Colors.grey.shade400 : color),
        onPressed: onTap,
        style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback onTap) =>
    ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

  Widget _compactBtn(String label, Color bg, VoidCallback onTap) => ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 14)),
    child: Text(label),
  );

  // ── Stats Cards ─────────────────────────────────────────────────────────────
  Widget _buildStatsCards() {
    double totalReceived = 0;
    double thisMonth = 0;
    final now = DateTime.now();
    for (var p in filteredPayments) {
      final amount = (p['amount'] ?? 0.0) as num;
      totalReceived += amount.toDouble();
      try {
        final parts = (p['date'] ?? '').split('/');
        if (parts.length == 3) {
          if (int.parse(parts[1]) == now.month && int.parse(parts[2]) == now.year) {
            thisMonth += amount.toDouble();
          }
        }
      } catch (_) {}
    }
    final cards = [
      _SC('Total Received', '₹${totalReceived.toStringAsFixed(2)}', Icons.attach_money, Colors.green),
      _SC('This Month',     '₹${thisMonth.toStringAsFixed(2)}',     Icons.calendar_today, Colors.blue),
      _SC('Total Payments', filteredPayments.length.toString(),      Icons.receipt_long,   Colors.purple),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth < 600) {
          return Wrap(spacing: 12, runSpacing: 12,
            children: cards.map((s) => SizedBox(width: (c.maxWidth - 12) / 2, child: _statCard(s))).toList());
        }
        return Row(children: cards.map((s) =>
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _statCard(s)))).toList());
      }),
    );
  }

  Widget _statCard(_SC s) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: s.color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: s.color.withOpacity(0.25)),
    ),
    child: Row(children: [
      Icon(s.icon, size: 30, color: s.color),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Text(s.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: s.color), overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );

  // ── Table Section ───────────────────────────────────────────────────────────
  Widget _buildTableSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: isLoading
          ? const SizedBox(height: 340, child: Center(child: CircularProgressIndicator()))
          : filteredPayments.isEmpty
              ? _emptyState()
              : _table(),
    );
  }

  Widget _table() {
    return Scrollbar(
      controller: _hScrollCtrl,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: 7,
      radius: const Radius.circular(4),
      notificationPredicate: (n) => n.depth == 1,
      child: Scrollbar(
        controller: _vScrollCtrl,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 7,
        radius: const Radius.circular(4),
        notificationPredicate: (n) => n.depth == 0,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: true,
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
          ),
          child: SingleChildScrollView(
            controller: _vScrollCtrl,
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              controller: _hScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF1A252F)),
                headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.4),
                headingRowHeight: 48,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 68,
                dataTextStyle: const TextStyle(fontSize: 15, color: _dark),
                dividerThickness: 0.8,
                columnSpacing: 16,
                horizontalMargin: 14,
                columns: const [
                  DataColumn(label: SizedBox(width: 100, child: Text('DATE'))),
                  DataColumn(label: SizedBox(width: 130, child: Text('PAYMENT #'))),
                  DataColumn(label: SizedBox(width: 120, child: Text('REFERENCE'))),
                  DataColumn(label: SizedBox(width: 160, child: Text('CUSTOMER'))),
                  DataColumn(label: SizedBox(width: 120, child: Text('INVOICE #'))),
                  DataColumn(label: SizedBox(width: 110, child: Text('MODE'))),
                  DataColumn(label: SizedBox(width: 110, child: Text('AMOUNT'))),
                  DataColumn(label: SizedBox(width: 80,  child: Text('PROOFS'))),
                  DataColumn(label: SizedBox(width: 60,  child: Text('ACTIONS'))),
                ],
                rows: filteredPayments.map(_buildRow).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(Map<String, dynamic> p) {
    return DataRow(
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.hovered)) return _primary.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(SizedBox(width: 100, child: Text(p['date'] ?? '', style: const TextStyle(fontSize: 14)))),

        // Payment # — clickable
        DataCell(SizedBox(width: 130,
          child: InkWell(
            onTap: () => _viewPaymentDetails(p),
            child: Text(p['paymentNumber']?.toString() ?? '',
              style: const TextStyle(color: _primary, fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline, fontSize: 15)),
          ),
        )),

        DataCell(SizedBox(width: 120,
          child: Text(p['referenceNumber'] ?? '-',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]), overflow: TextOverflow.ellipsis))),

        DataCell(SizedBox(width: 160,
          child: Text(p['customerName'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis))),

        DataCell(SizedBox(width: 120,
          child: Text(p['invoiceNumber'] ?? '-',
            style: const TextStyle(color: _primary, fontWeight: FontWeight.w500, fontSize: 14),
            overflow: TextOverflow.ellipsis))),

        DataCell(SizedBox(width: 110, child: Text(p['mode'] ?? '', style: const TextStyle(fontSize: 14)))),

        DataCell(SizedBox(width: 110,
          child: Text('₹${(p['amount'] ?? 0.0).toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)))),

        // Proofs
        DataCell(SizedBox(width: 80,
          child: p['hasProofs'] == true
              ? InkWell(
                  onTap: () => _viewPaymentProofs(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.attach_file, size: 14, color: Color(0xFF27AE60)),
                      const SizedBox(width: 4),
                      Text('${p['proofsCount'] ?? 0}',
                        style: const TextStyle(color: Color(0xFF27AE60), fontWeight: FontWeight.w600, fontSize: 14)),
                    ]),
                  ),
                )
              : Text('-', style: TextStyle(color: Colors.grey[400], fontSize: 15)),
        )),

        // Actions
        DataCell(SizedBox(width: 60,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (v) {
              switch (v) {
                case 'view':   _viewPaymentDetails(p); break;
                case 'proofs': _viewPaymentProofs(p);  break;
                case 'delete': _deletePayment(p);      break;
              }
            },
            itemBuilder: (_) => [
              _menuItem('view',   Icons.visibility_outlined, 'View Details', Colors.blue),
              if (p['hasProofs'] == true)
                _menuItem('proofs', Icons.attach_file, 'View Proofs', Colors.green),
              const PopupMenuDivider(),
              _menuItem('delete', Icons.delete_outline, 'Delete', Colors.red),
            ],
          ),
        )),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String val, IconData icon, String label, Color color) =>
    PopupMenuItem<String>(
      value: val,
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 15)),
      ]),
    );

  Widget _emptyState() => SizedBox(
    height: 340,
    child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
      const SizedBox(height: 16),
      Text(payments.isEmpty ? 'No payments found' : 'No payments match your filters',
        style: TextStyle(color: Colors.grey[600], fontSize: 18)),
      if (payments.isNotEmpty && (searchQuery.isNotEmpty || _hasDateFilters)) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () { setState(() { _searchCtrl.clear(); searchQuery = ''; fromDate = null; toDate = null; _applyFilters(); }); },
          icon: const Icon(Icons.clear_all),
          label: const Text('Clear All Filters'),
        ),
      ],
    ])),
  );
}

// ============================================================================
// STAT CARD DATA
// ============================================================================
class _SC {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SC(this.label, this.value, this.icon, this.color);
}

// ============================================================================
// PAYMENT DETAILS DIALOG
// ============================================================================
class PaymentDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> payment;
  const PaymentDetailsDialog({Key? key, required this.payment}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text('Payment #${payment['paymentNumber']}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row('Customer',  payment['customerName']   ?? ''),
          _row('Amount',    '₹${(payment['amount'] ?? 0.0).toStringAsFixed(2)}'),
          _row('Date',      payment['date']           ?? ''),
          _row('Mode',      payment['mode']           ?? ''),
          _row('Reference', payment['referenceNumber']?? '-'),
          _row('Invoice',   payment['invoiceNumber']  ?? '-'),
          if (payment['hasProofs'] == true)
            _row('Proofs', '${payment['proofsCount']} file(s) attached'),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey))),
      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
    ]),
  );
}

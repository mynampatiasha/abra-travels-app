// lib/features/client/presentation/screens/client_trip_dashboard_part2.dart
// ============================================================================
// CLIENT TRIP DASHBOARD - PART 2 OF 2
// ============================================================================
// ✅ ENHANCED TABLE with larger fonts and better spacing:
//    - Headers: 14px bold
//    - Data cells: 13px regular
//    - Improved cell padding and spacing
// ✅ Click row → Navigate to AdminTripDetails
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/features/admin/admin_trip_details.dart';
import 'client_trip_dashboard_part1.dart';
import 'client_trip_details.dart'; 

// ============================================================================
// ENHANCED TRIP TABLE SECTION
// ============================================================================
class TripTableSectionEnhanced extends StatefulWidget {
  final ClientTripDashboardState state;
  const TripTableSectionEnhanced({super.key, required this.state});

  @override
  State<TripTableSectionEnhanced> createState() => _TripTableSectionEnhancedState();
}

class _TripTableSectionEnhancedState extends State<TripTableSectionEnhanced> {
  // Sorted column tracking
  int? _sortColumnIndex;
  bool _sortAscending = true;

  // ─── Column definitions with ENHANCED WIDTHS ──────────────────────────────
  static const List<_ColumnDef> _columns = [
    _ColumnDef(key: 'tripNumber',    label: 'Trip #',        width: 130, sortable: true),
    _ColumnDef(key: 'vehicleNumber', label: 'Vehicle No.',   width: 140, sortable: true),
    _ColumnDef(key: 'vehicleName',   label: 'Vehicle Name',  width: 150, sortable: false),
    _ColumnDef(key: 'driverName',    label: 'Driver Name',   width: 160, sortable: true),
    _ColumnDef(key: 'driverPhone',   label: 'Driver Phone',  width: 140, sortable: false),
    _ColumnDef(key: 'scheduledDate', label: 'Date',          width: 130, sortable: true),
    _ColumnDef(key: 'time',          label: 'Scheduled Time',width: 140, sortable: false),
    _ColumnDef(key: 'customerCount', label: 'Customers',     width: 110, sortable: true),
    _ColumnDef(key: 'totalStops',    label: 'Total Stops',   width: 110, sortable: true),
    _ColumnDef(key: 'completedStops',label: 'Completed',     width: 110, sortable: true),
    _ColumnDef(key: 'cancelledStops',label: 'Cancelled',     width: 110, sortable: true),
    _ColumnDef(key: 'totalDistance', label: 'Distance (km)', width: 130, sortable: true),
    _ColumnDef(key: 'totalTime',     label: 'Duration (min)',width: 130, sortable: false),
    _ColumnDef(key: 'status',        label: 'Status',        width: 130, sortable: true),
    _ColumnDef(key: 'progress',      label: 'Progress',      width: 130, sortable: true),
    _ColumnDef(key: 'tripType',      label: 'Trip Type',     width: 120, sortable: false),
    _ColumnDef(key: 'actualStart',   label: 'Actual Start',  width: 130, sortable: false),
    _ColumnDef(key: 'actualEnd',     label: 'Actual End',    width: 130, sortable: false),
    _ColumnDef(key: 'actions',       label: 'Actions',       width: 110, sortable: false),
  ];

  // ─── Sort logic ───────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _sortedTrips {
    final trips = List<Map<String, dynamic>>.from(widget.state.trips);
    if (_sortColumnIndex == null) return trips;

    final col = _columns[_sortColumnIndex!];
    trips.sort((a, b) {
      dynamic va = a[col.key];
      dynamic vb = b[col.key];
      if (va == null && vb == null) return 0;
      if (va == null) return _sortAscending ? 1 : -1;
      if (vb == null) return _sortAscending ? -1 : 1;
      int cmp;
      if (va is num && vb is num) {
        cmp = va.compareTo(vb);
      } else {
        cmp = va.toString().compareTo(vb.toString());
      }
      return _sortAscending ? cmp : -cmp;
    });
    return trips;
  }

  Color _getStatusColor(String status) => widget.state.getStatusColor(status);
  String _getStatusText(String status) => widget.state.getStatusText(status);

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try { return DateFormat('dd MMM yyyy').format(DateTime.parse(raw)); } catch (_) { return raw; }
  }

  String _formatTime(dynamic dt) {
    if (dt == null) return '—';
    try { return DateFormat('HH:mm').format(DateTime.parse(dt.toString())); } catch (_) { return '—'; }
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(),
          const SizedBox(height: 10),
          _buildStatusTabBar(),
          const SizedBox(height: 10),
          _buildTableCard(),
          if (widget.state.totalPages > 1) _buildPagination(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Section header ───────────────────────────────────────────────────────
  Widget _buildSectionHeader() {
    final statusLabel = widget.state.selectedStatus == 'all'
        ? 'All Trips'
        : widget.state.selectedStatus[0].toUpperCase() + widget.state.selectedStatus.substring(1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Text('$statusLabel Trips',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
              if (widget.state.clientOrgName != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.state.clientOrgName!,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0891B2)),
                  ),
                ),
              ],
            ],
          ),
          Text('${widget.state.totalCount} records found',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ]),
        if (widget.state.totalPages > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF0D47A1).withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
            child: Text('Page ${widget.state.currentPage} / ${widget.state.totalPages}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0D47A1))),
          ),
      ],
    );
  }

  // ─── Status tab bar ───────────────────────────────────────────────────────
  Widget _buildStatusTabBar() {
    final tabs = [
      _TabItem('all', 'All', Icons.stacked_bar_chart, const Color(0xFF0D47A1)),
      _TabItem('ongoing', 'Ongoing', Icons.directions_car, const Color(0xFF00BFA5)),
      _TabItem('scheduled', 'Scheduled', Icons.schedule, const Color(0xFF2979FF)),
      _TabItem('completed', 'Completed', Icons.check_circle, const Color(0xFF43A047)),
      _TabItem('cancelled', 'Cancelled', Icons.cancel, const Color(0xFFE53935)),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final isSelected = widget.state.selectedStatus == tab.status;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                widget.state.setState(() { widget.state.selectedStatus = tab.status; widget.state.currentPage = 1; });
                widget.state.loadTripList();
              },
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? tab.color : tab.color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: tab.color.withOpacity(isSelected ? 1.0 : 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(tab.icon, size: 15, color: isSelected ? Colors.white : tab.color),
                  const SizedBox(width: 6),
                  Text(tab.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : tab.color)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Table card ───────────────────────────────────────────────────────────
  Widget _buildTableCard() {
    if (widget.state.isLoadingTrips) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading trips...'),
        ]),
      );
    }

    if (widget.state.trips.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
        ),
        child: Column(children: [
          Icon(Icons.inbox_rounded, size: 72, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Text('No trips found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Adjust your filters or date range', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          if (widget.state.hasActiveFilters) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: widget.state.clearAllFilters,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear All Filters'),
            ),
          ],
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: true,
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Scrollbar(
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 8,
                radius: const Radius.circular(4),
                notificationPredicate: (n) => n.depth == 1,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: _buildDataTable(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Data table with ENHANCED STYLING ─────────────────────────────────────
  Widget _buildDataTable() {
    final sorted = _sortedTrips;

    return DataTable(
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      headingRowHeight: 52, // ✅ Increased header height
      dataRowMinHeight: 56,  // ✅ Increased row min height
      dataRowMaxHeight: 64,  // ✅ Increased row max height
      dividerThickness: 0.8,
      columnSpacing: 24,     // ✅ Increased column spacing
      horizontalMargin: 20,  // ✅ Increased horizontal margin
      // Blue gradient header
      headingRowColor: WidgetStateProperty.all(const Color(0xFF0D47A1)),
      headingTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 14,        // ✅ HEADER: 14px
        letterSpacing: 0.3,
      ),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.blue.shade50;
        if (states.contains(WidgetState.hovered)) return const Color(0xFFF0F4FF);
        return null;
      }),
      columns: _buildColumns(),
      rows: sorted.asMap().entries.map((entry) => _buildDataRow(context, entry.key, entry.value)).toList(),
    );
  }

  List<DataColumn> _buildColumns() {
    return _columns.asMap().entries.map((entry) {
      final i = entry.key;
      final col = entry.value;
      return DataColumn(
        label: MouseRegion(
          cursor: col.sortable ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: SizedBox(
            width: col.width,
            child: Row(children: [
              Flexible(
                child: Text(col.label, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), // ✅ 14px
              ),
              if (col.sortable) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortColumnIndex == i
                      ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                      : Icons.unfold_more,
                  size: 16, color: Colors.white70,
                ),
              ],
            ]),
          ),
        ),
        numeric: false,
        onSort: col.sortable
            ? (colIndex, ascending) {
                setState(() {
                  _sortColumnIndex = colIndex;
                  _sortAscending = ascending;
                });
              }
            : null,
      );
    }).toList();
  }

  DataRow _buildDataRow(BuildContext context, int index, Map<String, dynamic> trip) {
    final status = trip['status']?.toString() ?? 'assigned';
    final progress = (trip['progress'] ?? 0).toDouble();
    final isDelayed = trip['isDelayed'] == true;
    Color statusColor = _getStatusColor(status);
    if (isDelayed) statusColor = const Color(0xFFE53935);
    final isEven = index % 2 == 0;

    return DataRow(
      onSelectChanged: (_) {
      // ✅ FIXED: Navigate to ClientTripDetails
      final tripId = _extractTripId(trip['_id']);
      if (tripId.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ClientTripDetails(tripId: tripId),  // ✅ NEW
          ),
        );
      }
    },
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return const Color(0xFFE8F0FE);
        return isEven ? Colors.white : const Color(0xFFF8FAFF);
      }),
      cells: [
        // Trip #
        _cell(130, child: Text(trip['tripNumber'] ?? 'N/A',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)))), // ✅ 13px

        // Vehicle No.
        _cell(140, child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(child: Text(trip['vehicleNumber'] ?? '—', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)), // ✅ 13px
        ])),

        // Vehicle Name
        _cell(150, child: Text(trip['vehicleName']?.toString().isNotEmpty == true ? trip['vehicleName'] : '—',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)), // ✅ 13px

        // Driver Name
        _cell(160, child: Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF0D47A1).withOpacity(0.12),
            child: Text(
              (trip['driverName']?.toString() ?? 'U').substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(trip['driverName'] ?? '—',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)), // ✅ 13px
        ])),

        // Driver Phone
        _cell(140, child: Text(trip['driverPhone']?.toString().isNotEmpty == true ? trip['driverPhone'] : '—',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700))), // ✅ 13px

        // Date
        _cell(130, child: Text(_formatDate(trip['scheduledDate']?.toString()),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))), // ✅ 13px

        // Time
        _cell(140, child: Text('${trip['startTime'] ?? '—'} → ${trip['endTime'] ?? '—'}',
            style: const TextStyle(fontSize: 12))), // ✅ 12px for compact time

        // Customers
        _cell(110, child: _countBadge(trip['customerCount'] ?? 0, const Color(0xFF8E24AA))),

        // Total Stops
        _cell(110, child: _countBadge(trip['totalStops'] ?? 0, const Color(0xFF1E88E5))),

        // Completed
        _cell(110, child: _countBadge(trip['completedStops'] ?? 0, const Color(0xFF43A047))),

        // Cancelled
        _cell(110, child: _countBadge(trip['cancelledStops'] ?? 0,
            (trip['cancelledStops'] ?? 0) > 0 ? const Color(0xFFE53935) : Colors.grey)),

        // Distance
        _cell(130, child: Row(children: [
          const Icon(Icons.route, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text('${(trip['totalDistance'] ?? 0).toStringAsFixed(1)} km', style: const TextStyle(fontSize: 13)), // ✅ 13px
        ])),

        // Duration
        _cell(130, child: Text(
          trip['totalTime'] != null && trip['totalTime'] != 0 ? '${trip['totalTime']} min' : '—',
          style: const TextStyle(fontSize: 13), // ✅ 13px
        )),

        // Status badge
        _cell(130, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // ✅ Increased padding
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withOpacity(0.4)),
          ),
          child: Text(_getStatusText(status),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor), textAlign: TextAlign.center),
        )),

        // Progress
        _cell(130, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${progress.toInt()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)), // ✅ 12px
            if (isDelayed)
              const Row(children: [
                Icon(Icons.warning_amber, size: 12, color: Color(0xFFE53935)),
                SizedBox(width: 2),
                Text('Late', style: TextStyle(fontSize: 9, color: Color(0xFFE53935))),
              ]),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 8, // ✅ Increased progress bar height
            ),
          ),
        ])),

        // Trip Type
        _cell(120, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), // ✅ Increased padding
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(trip['tripType']?.toString().toUpperCase() ?? '—',
              style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontWeight: FontWeight.w600)),
        )),

        // Actual Start
        _cell(130, child: Text(_formatTime(trip['actualStartTime']), 
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700))), // ✅ 12px

        // Actual End
        _cell(130, child: Text(_formatTime(trip['actualEndTime']), 
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700))), // ✅ 12px

        // Actions
        _cell(110, child: ElevatedButton(
          onPressed: () {
            final tripId = widget.state.extractTripId(trip['_id']);
            if (tripId.isEmpty) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => AdminTripDetails(tripId: tripId)));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D47A1),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // ✅ Increased padding
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          child: const Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), // ✅ 12px
        )),
      ],
    );
  }

  // ─── Cell helper ──────────────────────────────────────────────────────────
  DataCell _cell(double width, {required Widget child}) {
    return DataCell(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4), // ✅ Added vertical padding
        child: SizedBox(width: width, child: child),
      ),
    );
  }

  Widget _countBadge(int count, Color color) {
    return Container(
      width: 45, // ✅ Slightly larger badge
      padding: const EdgeInsets.symmetric(vertical: 5), // ✅ Increased padding
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$count',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)), // ✅ 13px
    );
  }

  // ─── Pagination ───────────────────────────────────────────────────────────
  Widget _buildPagination() {
    final s = widget.state;
    final totalPages = s.totalPages;
    final currentPage = s.currentPage;

    final pages = <int>[];
    final start = (currentPage - 2).clamp(1, (totalPages - 4).clamp(1, totalPages));
    final end = (start + 4).clamp(1, totalPages);
    for (int i = start; i <= end; i++) pages.add(i);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pageBtn(Icons.first_page, currentPage > 1, () { s.setState(() => s.currentPage = 1); s.loadTripList(); }),
          const SizedBox(width: 4),
          _pageBtn(Icons.chevron_left, currentPage > 1, () { s.setState(() => s.currentPage--); s.loadTripList(); }),
          const SizedBox(width: 8),
          ...pages.map((p) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: () { s.setState(() => s.currentPage = p); s.loadTripList(); },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: p == currentPage ? const Color(0xFF0D47A1) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p == currentPage ? const Color(0xFF0D47A1) : Colors.grey.shade300),
                ),
                alignment: Alignment.center,
                child: Text('$p',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: p == currentPage ? Colors.white : Colors.grey.shade700,
                    )),
              ),
            ),
          )),
          const SizedBox(width: 8),
          _pageBtn(Icons.chevron_right, currentPage < totalPages, () { s.setState(() => s.currentPage++); s.loadTripList(); }),
          const SizedBox(width: 4),
          _pageBtn(Icons.last_page, currentPage < totalPages, () { s.setState(() => s.currentPage = totalPages); s.loadTripList(); }),
          const SizedBox(width: 16),
          Text('${s.totalCount} total', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _pageBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: enabled ? Colors.grey.shade300 : Colors.grey.shade200),
        ),
        child: Icon(icon, size: 18, color: enabled ? Colors.grey.shade700 : Colors.grey.shade300),
      ),
    );
  }

  // ─── Helper to extract trip ID ────────────────────────────────────────────
  String _extractTripId(dynamic id) {
    if (id == null) return '';
    if (id is Map) return (id['\$oid'] ?? id['oid'] ?? '').toString();
    return id.toString();
  }
}

// ─── Simple data classes ──────────────────────────────────────────────────────
class _ColumnDef {
  final String key;
  final String label;
  final double width;
  final bool sortable;
  const _ColumnDef({required this.key, required this.label, required this.width, required this.sortable});
}

class _TabItem {
  final String status;
  final String label;
  final IconData icon;
  final Color color;
  const _TabItem(this.status, this.label, this.icon, this.color);
}

// ============================================================================
// OVERRIDE _TripTableWidget in Part 1 to use enhanced table
// ============================================================================
// Add this extension to Part 1's _TripTableWidget class:

extension ClientTripTableOverride on ClientTripDashboardState {
  Widget buildEnhancedTripTable() {
    return TripTableSectionEnhanced(state: this);
  }
}

// ============================================================================
// UPDATE Part 1's _TripTableWidget.build() method:
// ============================================================================
// Replace the _TripTableWidget class in Part 1 with:
/*
class _TripTableWidget extends StatelessWidget {
  final ClientTripDashboardState state;
  const _TripTableWidget({required this.state});

  @override
  Widget build(BuildContext context) {
    return TripTableSectionEnhanced(state: state);
  }
}
*/
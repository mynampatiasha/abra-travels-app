# Responsive phone-layout audit - 2026-11-17

Read-only static audit (target widths 360 and 412 px) of the working tree on 2026-11-17. No Dart file was edited. The tree has about 54 files modified by other sessions, so line numbers can drift by a few lines. Files with `backup`, `.bak`, `before`, `old` in the name, and `*.g.dart`, were ignored.

## 1. Summary

Live Dart files under `lib/`: **497**. 301 contain UI (build methods) and are in the table; 196 are non-UI (services, models, providers, repositories) and are listed by folder at the end of section 2.

| Severity | Meaning | All UI files | Client portal files |
|---|---|---|---|
| High | real overflow or unusable on a phone | 24 | 9 |
| Medium | usable but cramped, or unverified risk | 84 | 9 |
| Low | fine, dead code, or non-visual | 193 | 8 |

Key facts:

- **There is no shared responsive helper in the app** (no Responsive/Breakpoints class in `lib/`). Each screen re-implements `MediaQuery.size.width < 768` or nothing. Only about 47 files mention isMobile/Responsive at all.
- Client portal files (section 1 of the scope) were read by hand: the 9 High rows there are the pages the user observed plus the trip dashboard, table-heavy pages and bulk import.
- Other roles (admin, driver, customer, HRM, auth, notifications, TMS) were rated by **heuristics only** (grep for fixed widths >= 300, DataTable, Row counts, presence of MediaQuery/LayoutBuilder/isMobile). Treat their ratings as a triage list, not proof; Medium there means "not verified".
- Dead/orphan client files (not imported by anything): `client_reports_analytics.dart`, `_simple`, `_working`, `client_profile_screen.dart`, `client_reports_dashboard.dart` (1 line), and, per grep, also `leave_request_management.dart`, `organization_shift_config_screen.dart`, `client_billing_invoices.dart` (class `BillingInvoicesPage`), `client_feedback_management.dart`. Do not spend fix time on these unless they are wired in.
- Many pages already scroll horizontally for wide tables and filter bars (client_all_trips, trip dashboard, employee table). That avoids overflow errors but still leaves the content hidden sideways; the fix is card lists and wrapping, not more scrolling.

## 2. Ranked table of all UI screen files

Order: High, then Medium, then Low; client portal first inside each level, then by guessed use. Use is a guess from the file name. Effort: S under 1 h, M 1-3 h, L more.

| # | File | Area | Use | Sev | What overflows or is cramped (approx lines) | Suggested phone-only fix | Eff |
|---|---|---|---|---|---|---|---|
| 1 | `features/client/bulk_import_rosters.dart` | Client portal | Medium (roster/employee bulk import) | High | DataTable preview with 120 px columns (L657-709) in horizontal scroll, fixed 150 px drop zone (L272), 20 Rows; 4 MediaQuery; 6 dialogs. Preview table unusable on phone beyond 3 columns; stepper/header buttons Row not wrapped. | Phone: show first-N errors as cards, keep table sideways; wrap action buttons; phone dialog helper. | M |
| 2 | `features/client/client_all_trips.dart` | Client portal | Very high (My Trip Requests tab) | High | AppBar fine. Row 1 (L~740-800): Expanded status-chip list then New Trip + Export Excel ElevatedButtons with 16 px padding squeezes the chips to ~100 px and may overflow; Row 2 search is fixed 220 px (L689-690) next to chips; filter bar L1572+ is a single Row inside a horizontal SingleChildScrollView with fixed SizedBox 148 (From/To/Country dropdowns L1646-1672, 1807, min 100 max 160): no overflow error but the first screen shows only part of the filters (hidden sideways); table body is a 1530 px sum-of-columns SizedBox (L1007) in horizontal scroll; dialogs L357, 1257, 1872 use AlertDialog with unconstrained content (L1879 SizedBox). | Wrap the New Trip/Export row (or put Export in a popup menu), make search full width on its own line, turn filters into a Wrap or one "Filters" button that opens a bottom sheet, card list instead of 1530 px table, dialogs width = min(screen-32, 440). | M |
| 3 | `features/client/client_based_all_vehicles.dart` | Client portal | High (bottom-nav tab, live map) | High | Partly handled: isMobile used 8 times. Vehicle list panel is Positioned width 300 (85% of width only when width <=350, L836-842) so on 393 px it is 300 px (76% of screen) over the map; details panel Positioned width 350 (L1276) which is wider than a 360 px screen when both are open; fixed 60 px stats bar at bottom (bottom: 60); AppBar has several actions (filters, alerts badge) that crowd the title; filter and alerts AlertDialog L1480/L1576 use content SizedBox without width cap. | On phone: map full screen, vehicle list as a DraggableScrollableSheet (snap 15%/50%/90%), details as a modal bottom sheet, filters in a bottom sheet, stats bar as horizontally scrollable chips (MapSidePanelToSheet helper). | M |
| 4 | `features/client/client_dashboard_analytics.dart` | Client portal | Very high (home Analytics Overview) | High | Section header Row (L451-480): title text, "Live Data" chip, Spacer, Refresh button; no Flexible/Wrap, so on phone the Refresh button is clipped (user observed). isMobile only changes font size. 9 isMobile refs, 1 Wrap. | Use PhoneHeaderRow: title and chip in Wrap, Refresh as icon-only IconButton on phone. | S |
| 5 | `features/client/client_employee_management.dart` | Client portal | Very high (bottom-nav tab) | High | Header Row(spaceBetween) L~348 has a title Column plus a Wrap of 4 buttons (Refresh, Add Employee, Bulk Upload, Export) with no Expanded, so the buttons run off the right edge; padding 24 everywhere; table is a fixed 1340 px SizedBox inside a horizontal scroll (L549-566, header row duplicated for the same width) with a nested vertical scroll capped at 50% height; only 1 MediaQuery; add/bulk-import overlays and dialogs (AlertDialog L1361, maxWidth 800 L813) not phone-sized. | Header: title row then actions in Wrap or icon-only buttons (PhoneHeaderRow). Below 600 px render employees as cards (name, email, status, popup menu) instead of the 1340 px table. Padding 12. Overlays become full-screen pages. | M |
| 6 | `features/client/client_reports_analytics_enhanced.dart` | Client portal | High (Reports tab) | High | No MediaQuery; tab row of report types clipped ("Rost...") because tabs are fixed-label Rows/chips (L940-975 checkbox chips, TabBar-like row); action row PDF/Excel/WhatsApp is Row of Expanded (L762) tight at 360 px but fits; summary cards are horizontal ListViews of fixed 160 px width (L1168-1238, 1450-1468: 140/160 px with height 120); fixed heights 100-220 for charts (L670, 1276, 1346, 1504); grid crossAxisCount 3 when <600 (L1571) too dense; Wrap used in legends. | Make tab strip scrollable (isScrollable: true / ScrollableTabs helper), stack filter selectors in Wrap, summary cards 2 columns, charts height by aspect ratio, grid crossAxisCount 2 on phone. | M |
| 7 | `features/client/client_sos_alerts.dart` | Client portal | High (bottom-nav SOS tab) | High | Partly responsive (6 MediaQuery, 1 LayoutBuilder, 2 isMobile). Tab content container has fixed height: 500 (L457) with a header Row(spaceBetween) (L383, 2099) containing title plus refresh/filters; TabBar (L411) with icon+text tabs not scrollable (2 tabs, may truncate); dialogs maxWidth 500/600 (L714, 2003) fine; fixed 120/100 px boxes (L1910, 2310, 2423); 26 Expanded/Flexible. | Replace fixed 500 height with Expanded/shrink to content (min of 60% screen); wrap header actions; shorten tab labels or Flexible text. | M |
| 8 | `features/client/client_trip_dashboard_part1.dart` | Client portal | Very high (Trips tab via shell, "Trip Dashboard") | High | No MediaQuery; 2 LayoutBuilders only. Filters section: search Expanded plus export-buttons Row Expanded(flex 4) side by side (L~880-890) which makes both unusably narrow on 360 px; Trip Overview title Row with org chip (L~1020) not wrapped; 22 Expanded/Flexible and 11 Rows; dropdown row L1259; status cards and charts reuse admin layouts. Part1 is also reused by ClientReportsAnalyticsEnhanced. | Stack search above export buttons on phone, Wrap the header chips, 2-column status cards, charts full width; phone dialogs. | M |
| 9 | `features/client/client_trip_dashboard_part2.dart` | Client portal | Very high (trip list table) | High | DataTable with 19 fixed-width columns (_columns L37-55, widths 110-160, about 2400 px total) plus columnSpacing 24 (L292-299); horizontal scroll exists but the whole table is not phone-usable; status tab bar is a horizontal SingleChildScrollView Row (L161-175, OK). Trip details opened from here. | Below 600 px show a card list (trip #, status, vehicle, driver, date/time, progress) with tap for details; keep DataTable for >=768. | M |
| 10 | `features/admin/admin_trip_details.dart` | Admin | High | High | DataTable/Table at L563; 27 Row() and no MediaQuery/LayoutBuilder/isMobile; 7 dialogs/sheets, none width-aware (2240 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | L |
| 11 | `features/admin/dashboard/presentation/screens/incomplete_sos_alerts_screen.dart` | Admin | High | High | fixed widths >=300 at L767(1280),863(480),1187(500); 15 Row() and no MediaQuery/LayoutBuilder/isMobile; 10 dialogs/sheets, none width-aware (1722 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 12 | `features/driver/dashboard/presentation/screens/reports_driver_page.dart` | Driver | High | High | fixed widths >=300 at L417(1000),791(400),837(400); 12 Row() and no MediaQuery/LayoutBuilder/isMobile; 15 dialogs/sheets, none width-aware (1249 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 13 | `features/admin/Billing/pages/import_transactions_dialog.dart` | Admin | Medium | High | fixed widths >=300 at L79(900); DataTable/Table at L519 (787 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 14 | `features/admin/Billing/pages/reconciliation_billing.dart` | Admin | Medium | High | fixed widths >=300 at L2512(650),3601(500),3741(600),3969(550); 75 Row() and no MediaQuery/LayoutBuilder/isMobile; 43 dialogs/sheets, none width-aware (5136 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | L |
| 15 | `features/admin/Billing/pages/recurring_expenses_list_page.dart` | Admin | Medium | High | fixed widths >=300 at L168(800),285(350),462(500),1000(600); 19 Row() and no MediaQuery/LayoutBuilder/isMobile; 11 dialogs/sheets, none width-aware (1963 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | L |
| 16 | `features/admin/Billing/rate_card_list.dart` | Admin | Medium | High | fixed widths >=300 at L462(500),513(500); 23 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1540 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 17 | `features/admin/admin_report_generator.dart` | Admin | Medium | High | DataTable/Table at L206,387; 9 Row() and no MediaQuery/LayoutBuilder/isMobile (648 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 18 | `features/admin/customer_management/admin_pending_customers_modified.dart` | Admin | Medium | High | DataTable/Table at L1482; 12 Row() and no MediaQuery/LayoutBuilder/isMobile (1550 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 19 | `features/admin/vehicle_admin_management/enhanced_fleet_map_screen.dart` | Admin | Medium | High | fixed widths >=300 at L576(350),1479(500); 21 Row() and no MediaQuery/LayoutBuilder/isMobile; 8 dialogs/sheets, none width-aware (1729 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 20 | `features/admin/vehicle_admin_management/vehicle_master/vehicle_master_redesigned_part3.dart` | Admin | Medium | High | fixed widths >=300 at L1490(1310); DataTable/Table at L753; 11 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1843 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | L |
| 21 | `features/TMS/all_tickets_IMPROVED.dart` | Tickets (TMS) | Low | High | DataTable/Table at L792; 12 Row() and no MediaQuery/LayoutBuilder/isMobile; 6 dialogs/sheets, none width-aware (1288 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 22 | `features/TMS/all_tickets_UPDATED.dart` | Tickets (TMS) | Low | High | DataTable/Table at L998; 15 Row() and no MediaQuery/LayoutBuilder/isMobile; 6 dialogs/sheets, none width-aware (1527 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 23 | `features/admin/hrm/hrm_employee_list.dart` | HRM (admin) | Low | High | DataTable/Table at L509 (718 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 24 | `features/admin/hrm/hrm_employees_screen.dart` | HRM (admin) | Low | High | fixed widths >=300 at L126(600),571(600); DataTable/Table at L1212; 14 Row() and no MediaQuery/LayoutBuilder/isMobile; 8 dialogs/sheets, none width-aware (1303 lines) | Wrap/Expanded toolbars, table-to-card list on phone, phone dialog width | M |
| 25 | `features/client/client_billing_invoices.dart` | Client portal | Low (BillingInvoicesPage not referenced by the client shell) | Medium | Already partly responsive: LayoutBuilder with isMobile < 600 (L701), title/actions Wrap (L895-960). Remaining: TabBar with 4 icon+text tabs not scrollable (L1028, labels Invoices/Contracts/Analytics/Audit Logs clip on 360), 54 Rows with spaceBetween money cells (L2139-2229, 2863-2955) without FittedBox, 22 dialogs, stat grid crossAxisCount 4 (L2056) with childAspectRatio 1.2. | Tab bar isScrollable; money Text inside FittedBox; stat grid 2 columns on phone. | M |
| 26 | `features/client/client_dashboard.dart` | Client portal | Very high (home) | Medium | Has 9 isMobile checks and 3 LayoutBuilders. Remaining: chart row Expanded flex 5/4/5 (L503-509) must stack on phone (verify); skeleton rows (L940-944); fixed heights 160-220 for chart cards (L542, 645, 716, 826) hold text; fixed 180 px skeleton boxes harmless. | Verify stacked layout at 360; give cards min-height not fixed height. | S |
| 27 | `features/client/client_feedback_management.dart` | Client portal | Low (not imported anywhere; HRMFeedbackScreen from admin/hrm/hrm_feedback.dart is the live one) | Medium | Tab bar with indicator container (L233) fixed label font 14; ConstrainedBox maxWidth 1100; grid already adapts (crossAxisCount 1 on narrow, L982-990); 16 Rows with spaceBetween (L1037, 1108). | Only fix if it is wired back in. | S |
| 28 | `features/client/client_profile_page.dart` | Client portal | Medium (Profile, in shell) | Medium | No MediaQuery/LayoutBuilder; maxWidth 700 constraint (L627) so it narrows safely; 100x100 avatar (L793); 10 Rows (label/value pairs, edit buttons) not verified; 5 dialogs/sheets. | Check Row(label, value) pairs for Expanded and long email wrapping. | S |
| 29 | `features/client/client_roster_management.dart` | Client portal | Very high (Employee/roster tab) | Medium | Already good: TabBar isScrollable true (L1079-1085), 2 MediaQuery + 2 LayoutBuilder + 4 Wrap. Remaining: 38 Rows and many dialogs (18) with maxWidth 500/600 constraints (L2914, 3126) which are fine, but filter/export dialogs (L1264, 1496) and fixed 120 px widths (L3095) need a phone check; bulk import and pending tab embedded. | Verify roster cards at 360 px; use shared phone dialog width helper. | S |
| 30 | `features/client/client_trip_details.dart` | Client portal | High (opened from trip list) | Medium | No MediaQuery, 1 LayoutBuilder. 25 Rows with spaceBetween label/value pairs (L1277, 1297, 1489, 1616) and some fixed 120 px label widths (L469); 3 table widgets; text in Row without Expanded can overflow on long driver/vehicle names. | Wrap label/value rows with Expanded/Flexible and ellipsis; make info grid 1 column on phone. | M |
| 31 | `features/client/leave_request_management.dart` | Client portal | Low (not referenced by the shell) | Medium | 2 MediaQuery + LayoutBuilder; 12 dialogs/sheets; fixed 120/200 px (L421, 619). | Check dialogs and card rows at 360. | S |
| 32 | `features/client/organization_shift_config_screen.dart` | Client portal | Low (not referenced; used via organization_model only) | Medium | 1 LayoutBuilder, 4 Wrap, 12 dialogs (ShiftEditorDialog) with no width cap; 9 Rows. | Cap dialog width; time pickers in Wrap. | S |
| 33 | `features/client/start_client_trip.dart` | Client portal | High ("Request New Trip", from My Trip Requests) | Medium | 2 LayoutBuilders, ConstrainedBox maxWidth 800 (L559) so it narrows; 14 Rows with date/time/passenger fields side by side likely unwrapped; 4 dialogs/sheets. | Stack paired fields on phone; verify pickers. | S |
| 34 | `features/admin/admin_trip_dashboard.dart` | Admin | High | Medium | fixed widths >=300 at L424(400); DataTable/Table at L1324,1797,1808 (2136 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 35 | `features/admin/client_management/admin_client_trips.dart` | Admin | High | Medium | fixed widths >=300 at L1104(300),1373(1200),1779(620),2632(300); DataTable/Table at L1376 (2985 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 36 | `features/admin/client_management/client_admin_dashboard_screen.dart` | Admin | High | Medium | fixed widths >=300 at L906(1200); DataTable/Table at L909 (1626 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 37 | `features/admin/customer_management/notification/approved_rosters_screen.dart` | Admin | High | Medium | fixed widths >=300 at L281(600); 18 Row() and no MediaQuery/LayoutBuilder/isMobile; 4 dialogs/sheets, none width-aware (976 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 38 | `features/admin/customer_management/notification/edit_roster_assignment_screen.dart` | Admin | High | Medium | 18 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1273 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 39 | `features/admin/customer_management/notification/roster_assignment_screen.dart` | Admin | High | Medium | 15 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1227 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 40 | `features/admin/customer_management/notification/rosters/group_details_dialog.dart` | Admin | High | Medium | fixed widths >=300 at L42(800); 11 Row() and no MediaQuery/LayoutBuilder/isMobile; 4 dialogs/sheets, none width-aware (557 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 41 | `features/admin/customer_management/notification/rosters/vehicle_selection_dialog.dart` | Admin | High | Medium | fixed widths >=300 at L245(700) (774 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 42 | `features/admin/customer_management/widgets/roster_assignment_dialog.dart` | Admin | High | Medium | fixed widths >=300 at L36(600); 4 dialogs/sheets, none width-aware (440 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 43 | `features/admin/vehicle_admin_management/consecutive_trips_admin.dart` | Admin | High | Medium | 26 Row() and no MediaQuery/LayoutBuilder/isMobile; 7 dialogs/sheets, none width-aware (2303 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 44 | `features/admin/vehicle_admin_management/trip_operations/emergency_alert_screen.dart` | Admin | High | Medium | 17 Row() and no MediaQuery/LayoutBuilder/isMobile; 8 dialogs/sheets, none width-aware (1108 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 45 | `features/admin/vehicle_admin_management/trip_operations/gps_tracking.dart` | Admin | High | Medium | fixed widths >=300 at L609(450); DataTable/Table at L1026 (1168 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 46 | `features/admin/vehicle_admin_management/trip_operations/trip_analytics_screen.dart` | Admin | High | Medium | 25 Row() and no MediaQuery/LayoutBuilder/isMobile; 14 dialogs/sheets, none width-aware (1982 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 47 | `features/admin/vehicle_admin_management/trip_operations/trip_operation.dart` | Admin | High | Medium | fixed widths >=300 at L635(600),1255(640),2259(1200); DataTable/Table at L2262 (2767 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 48 | `features/admin/vehicle_admin_management/trip_operations/trip_operations_list_screen.dart` | Admin | High | Medium | fixed widths >=300 at L647(500); 12 Row() and no MediaQuery/LayoutBuilder/isMobile; 4 dialogs/sheets, none width-aware (835 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 49 | `features/auth/presentation/screens/login_screen.dart` | Auth | High | Medium | fixed widths >=300 at L353(480) (843 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 50 | `features/customer/dashboard/presentation/screens/location_picker_screen.dart` | Customer/Employee | High | Medium | 16 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1287 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 51 | `features/customer/dashboard/presentation/screens/my_address_requests_screen.dart` | Customer/Employee | High | Medium | fixed widths >=300 at L114(900); 11 Row() and no MediaQuery/LayoutBuilder/isMobile (494 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 52 | `features/customer/dashboard/presentation/screens/my_trips_screen.dart` | Customer/Employee | High | Medium | 16 Row() and no MediaQuery/LayoutBuilder/isMobile; 5 dialogs/sheets, none width-aware (1842 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 53 | `features/driver/dashboard/presentation/screens/ex.dart` | Driver | High | Medium | fixed widths >=300 at L152(1024),224(1024); 9 Row() and no MediaQuery/LayoutBuilder/isMobile; 22 dialogs/sheets, none width-aware (2030 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 54 | `features/driver/dashboard/presentation/screens/profile_driver_page.dart` | Driver | High | Medium | fixed widths >=300 at L166(1024),238(1024); 23 dialogs/sheets, none width-aware (2152 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 55 | `features/driver/trip_reporting/presentation/screens/driver_trip_reporting_screen.dart` | Driver | High | Medium | fixed widths >=300 at L87(1000),586(700) (592 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 56 | `features/admin/Billing/pages/bill_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L399(500),2551(580); DataTable/Table at L2042,2110 (2753 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 57 | `features/admin/Billing/pages/budgets_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L794(340),795(340),822(340),1167(560); DataTable/Table at L574 (1272 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 58 | `features/admin/Billing/pages/chart_of_accounts_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L287(340),288(340),319(340),401(380); DataTable/Table at L1024 (1344 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 59 | `features/admin/Billing/pages/credit_notes_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L383(520); DataTable/Table at L1172 (1680 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 60 | `features/admin/Billing/pages/customers_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L1378(560); DataTable/Table at L884 (1735 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 61 | `features/admin/Billing/pages/delivery_challans_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L800(300); DataTable/Table at L1753 (1802 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 62 | `features/admin/Billing/pages/invoices_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L1862(560); DataTable/Table at L1195,2335 (2383 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 63 | `features/admin/Billing/pages/items_billing.dart` | Admin | Medium | Medium | fixed widths >=300 at L1653(600); 10 Row() and no MediaQuery/LayoutBuilder/isMobile; 8 dialogs/sheets, none width-aware (1957 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 64 | `features/admin/Billing/pages/manual_journals_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L154(700),858(480); DataTable/Table at L570 (919 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 65 | `features/admin/Billing/pages/new_item_billing.dart` | Admin | Medium | Medium | fixed widths >=300 at L753(400),878(400); 14 Row() and no MediaQuery/LayoutBuilder/isMobile; 7 dialogs/sheets, none width-aware (1059 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 66 | `features/admin/Billing/pages/payment_made_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L951(780),1141(520),1497(480),1552(560); DataTable/Table at L670,1019,1047 (1652 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 67 | `features/admin/Billing/pages/purchase_orders_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L1719(600),2656(600); DataTable/Table at L2146 (2880 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 68 | `features/admin/Billing/pages/quotes_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L2127(600); DataTable/Table at L2600 (2634 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 69 | `features/admin/Billing/pages/reconciliation_page.dart` | Admin | Medium | Medium | 20 Row() and no MediaQuery/LayoutBuilder/isMobile; 4 dialogs/sheets, none width-aware (1488 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 70 | `features/admin/Billing/pages/recurring_bills_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L147(480),445(600),1611(580); DataTable/Table at L1016 (1790 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 71 | `features/admin/Billing/pages/recurring_invoices_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L1265(520),1762(560),1889(600); DataTable/Table at L886 (1912 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 72 | `features/admin/Billing/pages/sales_orders_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L1821(600); DataTable/Table at L2194 (2228 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 73 | `features/admin/Billing/pages/vendor_credit_detail.dart` | Admin | Medium | Medium | fixed widths >=300 at L106(480),329(480),594(320); DataTable/Table at L716 (1073 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 74 | `features/admin/Billing/pages/vendor_credits_list_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L142(480),1344(560); DataTable/Table at L804 (1512 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 75 | `features/admin/client_management/client_billing_invoices.dart` | Admin | Medium | Medium | 43 Row() and no MediaQuery/LayoutBuilder/isMobile; 18 dialogs/sheets, none width-aware (2170 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 76 | `features/admin/customer_management/widgets/detailed_error_dialog.dart` | Admin | Medium | Medium | fixed widths >=300 at L25(600); 4 dialogs/sheets, none width-aware (377 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 77 | `features/admin/customer_management/widgets/route_optimization_dialog.dart` | Admin | Medium | Medium | fixed widths >=300 at L48(700); 13 Row() and no MediaQuery/LayoutBuilder/isMobile (737 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 78 | `features/admin/customer_management/widgets/vehicle_confirmation_dialog.dart` | Admin | Medium | Medium | fixed widths >=300 at L119(600); 10 Row() and no MediaQuery/LayoutBuilder/isMobile (552 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 79 | `features/admin/driver_admin_management/csv_import_dialog.dart` | Admin | Medium | Medium | fixed widths >=300 at L442(700); 8 dialogs/sheets, none width-aware (756 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 80 | `features/admin/driver_admin_management/driver_admin_management_dialogs.dart` | Admin | Medium | Medium | fixed widths >=300 at L1720(700),1912(500),2825(600),3214(600); DataTable/Table at L2510,3271 (3565 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 81 | `features/admin/driver_admin_management/driver_details_page.dart` | Admin | Medium | Medium | fixed widths >=300 at L993(500); 8 Row() and no MediaQuery/LayoutBuilder/isMobile; 9 dialogs/sheets, none width-aware (1178 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 82 | `features/admin/driver_admin_management/driver_feedback_list_screen.dart` | Admin | Medium | Medium | fixed widths >=300 at L1186(500),1255(400); 13 Row() and no MediaQuery/LayoutBuilder/isMobile; 4 dialogs/sheets, none width-aware (1471 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 83 | `features/admin/reports/presentation/screens/vehicle_performance_report_screen.dart` | Admin | Medium | Medium | DataTable/Table at L159 (183 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 84 | `features/admin/vehicle_admin_management/maintainace_managemnt/maintainance_management.dart` | Admin | Medium | Medium | fixed widths >=300 at L942(300); DataTable/Table at L1121 (1502 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 85 | `features/admin/vehicle_admin_management/reports_analytics/driver_performance_report.dart` | Admin | Medium | Medium | DataTable/Table at L78 (98 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 86 | `features/admin/vehicle_admin_management/reports_analytics/fuel_efficiency_report.dart` | Admin | Medium | Medium | DataTable/Table at L78 (98 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 87 | `features/admin/vehicle_admin_management/reports_analytics/vehicle_utilization_report.dart` | Admin | Medium | Medium | DataTable/Table at L78 (98 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 88 | `features/admin/vehicle_admin_management/vehicle_master/widgets/assigned_customers_dialog.dart` | Admin | Medium | Medium | fixed widths >=300 at L39(700) (419 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 89 | `features/hrm_feedback/presentation/screens/hrm_admin_feedback_screen.dart` | HRM feedback | Medium | Medium | 16 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1405 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 90 | `features/hrm_feedback/presentation/screens/hrm_client_feedback_screen.dart` | HRM feedback | Medium | Medium | 15 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1240 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 91 | `features/hrm_feedback/presentation/screens/hrm_customer_feedback_screen.dart` | HRM feedback | Medium | Medium | 16 Row() and no MediaQuery/LayoutBuilder/isMobile; 5 dialogs/sheets, none width-aware (1446 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 92 | `features/hrm_feedback/presentation/screens/hrm_departments_screen.dart` | HRM feedback | Medium | Medium | fixed widths >=300 at L572(400); DataTable/Table at L634 (695 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 93 | `features/hrm_feedback/presentation/screens/hrm_driver_feedback_screen.dart` | HRM feedback | Medium | Medium | 15 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1259 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 94 | `features/hrm_feedback/presentation/screens/hrm_notice_board_screen.dart` | HRM feedback | Medium | Medium | 19 Row() and no MediaQuery/LayoutBuilder/isMobile; 8 dialogs/sheets, none width-aware (1260 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 95 | `features/notifications/presentation/screens/customer_notifications_screen.dart` | Notifications | Medium | Medium | fixed widths >=300 at L991(500); 18 Row() and no MediaQuery/LayoutBuilder/isMobile; 8 dialogs/sheets, none width-aware (1926 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 96 | `features/TMS/ticket_detail_screen.dart` | Tickets (TMS) | Low | Medium | 21 Row() and no MediaQuery/LayoutBuilder/isMobile (1381 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 97 | `features/admin/ERP/erp_users_management_screen.dart` | Admin | Low | Medium | fixed widths >=300 at L775(300),839(300),1174(520),1398(480); DataTable/Table at L754 (1564 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 98 | `features/admin/hrm/hrm_add_employee.dart` | HRM (admin) | Low | Medium | 20 Row() and no MediaQuery/LayoutBuilder/isMobile; 8 dialogs/sheets, none width-aware (1725 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 99 | `features/admin/hrm/hrm_add_employee_screen.dart` | HRM (admin) | Low | Medium | 28 Row() and no MediaQuery/LayoutBuilder/isMobile (1640 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 100 | `features/admin/hrm/hrm_edit_employee_screen.dart` | HRM (admin) | Low | Medium | 24 Row() and no MediaQuery/LayoutBuilder/isMobile (1599 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 101 | `features/admin/hrm/hrm_master_settings_screen.dart` | HRM (admin) | Low | Medium | 16 Row() and no MediaQuery/LayoutBuilder/isMobile; 53 dialogs/sheets, none width-aware (2340 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 102 | `features/admin/role_based_access/user.dart` | Admin | Low | Medium | 16 Row() and no MediaQuery/LayoutBuilder/isMobile; 11 dialogs/sheets, none width-aware (1268 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 103 | `features/admin/role_based_access/user_management_screen.dart` | Admin | Low | Medium | fixed widths >=300 at L732(500); 9 Row() and no MediaQuery/LayoutBuilder/isMobile; 8 dialogs/sheets, none width-aware (949 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 104 | `features/admin/role_based_access/user_permission_dialog.dart` | Admin | Low | Medium | fixed widths >=300 at L351(900); 9 Row() and no MediaQuery/LayoutBuilder/isMobile (887 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 105 | `features/admin/role_based_access/user_permissions_screen.dart` | Admin | Low | Medium | DataTable/Table at L322 (520 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 106 | `features/admin/role_based_access/user_role_admin_access.dart` | Admin | Low | Medium | DataTable/Table at L641; 4 dialogs/sheets, none width-aware (787 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 107 | `features/admin/widgets/horizontal_filter_bar.dart` | Admin | Low | Medium | 18 Row() and no MediaQuery/LayoutBuilder/isMobile (931 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 108 | `features/auth/presentation/screens/registration_screen.dart` | Auth | Low | Medium | fixed widths >=300 at L212(560) (879 lines) | Spot-check rows/dialogs at 360 px; wrap button rows | S |
| 109 | `features/client/client_main_shell.dart` | Client portal | Very high (shell) | Low | Already responsive: breakpoint 768, mobile header, bottom nav (Home/Employee/Trips/SOS), home grid, 36 isMobile refs, 4 MediaQuery. 12 dialogs/sheets, fixed widths only at 2 places (check logout/profile dialogs). | No change; only check bottom-nav labels at 360. | S |
| 110 | `features/client/client_pending_assignment_tab.dart` | Client portal | Medium (roster sub-tab) | Low | 6 MediaQuery uses, 8 dialogs, fixed 120 px width at L945 only. Looks mostly fine. | Spot-check dialog widths at 360 px. | S |
| 111 | `features/client/client_profile_screen.dart` | Client portal | Unused (only a backup file imports it) | Low | Dead code, 1100 lines; 120x120 avatars, maxWidth 1100. Not reachable. | Delete or ignore. | S |
| 112 | `features/client/client_reports_analytics.dart` | Client portal | Unused (no imports) | Low | Dead, 8 Table widgets; no fixes. | Delete or ignore. | S |
| 113 | `features/client/client_reports_analytics_simple.dart` | Client portal | Unused (no imports) | Low | Dead, 192 lines. | Ignore. | S |
| 114 | `features/client/client_reports_analytics_working.dart` | Client portal | Unused (no imports) | Low | Dead, 8 Table widgets. | Ignore. | S |
| 115 | `features/client/client_reports_dashboard.dart` | Client portal | Imported by shell but file is 1 line (stub) | Low | Empty stub. | None. | S |
| 116 | `features/client/organization_model.dart` | Client portal | n/a (model) | Low | Non-UI. | None. | S |
| 117 | `core/services/multi_trip_service.dart` | Core/Shared | High | Low | no obvious fixed-width risk found (466 lines) | None expected | S |
| 118 | `core/services/roster_service.dart` | Core/Shared | High | Low | no obvious fixed-width risk found (1957 lines) | None expected | S |
| 119 | `features/admin/Billing/billing_main_shell.dart` | Admin | High | Low | has 1 MediaQuery/0 LayoutBuilder/4 isMobile checks (879 lines) | None expected | S |
| 120 | `features/admin/client_management/trips_client.dart` | Admin | High | Low | fixed widths >=300 at L1020(500) (1256 lines) | None expected | S |
| 121 | `features/admin/customer_management/notification/modified_pending_screen_edit_delete_pending_rosters.dart` | Admin | High | Low | fixed widths >=300 at L600(800),3416(600),6288(600),6853(680) (7346 lines) | None expected | S |
| 122 | `features/admin/customer_management/notification/rosters/assignment_dialog.dart` | Admin | High | Low | 3 dialogs/sheets, none width-aware (51 lines) | None expected | S |
| 123 | `features/admin/dashboard/presentation/screens/admin_dashboard_screen.dart` | Admin | High | Low | has 1 MediaQuery/0 LayoutBuilder/1 isMobile checks (1285 lines) | None expected | S |
| 124 | `features/admin/dashboard/presentation/screens/map_screen.dart` | Admin | High | Low | no obvious fixed-width risk found (90 lines) | None expected | S |
| 125 | `features/admin/dashboard/presentation/screens/resolved_alerts_view.dart` | Admin | High | Low | fixed widths >=300 at L973(600) (1267 lines) | None expected | S |
| 126 | `features/admin/dashboard/welcome_greeting_screen.dart` | Admin | High | Low | no obvious fixed-width risk found (82 lines) | None expected | S |
| 127 | `features/admin/driver_admin_management/trip_verification_screen.dart` | Admin | High | Low | fixed widths >=300 at L205(400),291(400),414(600),498(800) (1476 lines) | None expected | S |
| 128 | `features/admin/leave_trip_management.dart` | Admin | High | Low | fixed widths >=300 at L202(600) (1018 lines) | None expected | S |
| 129 | `features/admin/shell/admin_main_shell.dart` | Admin | High | Low | fixed widths >=300 at L859(600),1324(500),3014(500) (6520 lines) | None expected | S |
| 130 | `features/admin/test_trip_cancellation_simple.dart` | Admin | High | Low | no obvious fixed-width risk found (49 lines) | None expected | S |
| 131 | `features/admin/vehicle_admin_management/trip_operations/emergency_map_screen.dart` | Admin | High | Low | no obvious fixed-width risk found (634 lines) | None expected | S |
| 132 | `features/admin/vehicle_admin_management/trip_operations/live_map_screen.dart` | Admin | High | Low | has 2 MediaQuery/0 LayoutBuilder/0 isMobile checks (2685 lines) | None expected | S |
| 133 | `features/admin/vehicle_admin_management/trip_operations/route_selection_page.dart` | Admin | High | Low | 13 Row() and no MediaQuery/LayoutBuilder/isMobile (1197 lines) | None expected | S |
| 134 | `features/admin/vehicle_admin_management/trip_operations/send_notifications_screen.dart` | Admin | High | Low | 10 Row() and no MediaQuery/LayoutBuilder/isMobile (936 lines) | None expected | S |
| 135 | `features/admin/vehicle_admin_management/trip_operations/start_new_trip.dart` | Admin | High | Low | fixed widths >=300 at L1147(500) (1868 lines) | None expected | S |
| 136 | `features/admin/vehicle_admin_management/trip_operations/widgets/enhanced_location_search_widget.dart` | Admin | High | Low | no obvious fixed-width risk found (445 lines) | None expected | S |
| 137 | `features/admin/vehicle_admin_management/vehicle_dashboard.dart` | Admin | High | Low | no obvious fixed-width risk found (262 lines) | None expected | S |
| 138 | `features/admin/widgets/enhanced_dashboard_cards.dart` | Admin | High | Low | no obvious fixed-width risk found (563 lines) | None expected | S |
| 139 | `features/auth/presentation/screens/post_login_splash_screen.dart` | Auth | High | Low | fixed widths >=300 at L198(300) (475 lines) | None expected | S |
| 140 | `features/customer/dashboard/presentation/screens/address_change_request_screen.dart` | Customer/Employee | High | Low | fixed widths >=300 at L173(900) (436 lines) | None expected | S |
| 141 | `features/customer/dashboard/presentation/screens/customer_dashboard.dart` | Customer/Employee | High | Low | fixed widths >=300 at L2511(420) (3927 lines) | None expected | S |
| 142 | `features/customer/dashboard/presentation/screens/customer_dashboard_temp.dart` | Customer/Employee | High | Low | has 3 MediaQuery/0 LayoutBuilder/64 isMobile checks (2401 lines) | None expected | S |
| 143 | `features/customer/dashboard/presentation/screens/customer_main_parent_screen.dart` | Customer/Employee | High | Low | has 1 MediaQuery/0 LayoutBuilder/0 isMobile checks (379 lines) | None expected | S |
| 144 | `features/customer/dashboard/presentation/screens/customer_profile_screen.dart` | Customer/Employee | High | Low | fixed widths >=300 at L192(800),563(900) (1289 lines) | None expected | S |
| 145 | `features/customer/dashboard/presentation/screens/enhanced_tracking_screen.dart` | Customer/Employee | High | Low | has 7 MediaQuery/1 LayoutBuilder/0 isMobile checks (1770 lines) | None expected | S |
| 146 | `features/customer/dashboard/presentation/screens/leave_request_screen.dart` | Customer/Employee | High | Low | fixed widths >=300 at L190(900) (442 lines) | None expected | S |
| 147 | `features/customer/dashboard/presentation/screens/my_leave_requests_screen.dart` | Customer/Employee | High | Low | fixed widths >=300 at L135(900) (455 lines) | None expected | S |
| 148 | `features/customer/dashboard/presentation/screens/mystats_screen.dart` | Customer/Employee | High | Low | has 1 MediaQuery/1 LayoutBuilder/16 isMobile checks (1579 lines) | None expected | S |
| 149 | `features/customer/dashboard/presentation/screens/roster_screen.dart` | Customer/Employee | High | Low | has 1 MediaQuery/0 LayoutBuilder/0 isMobile checks (1739 lines) | None expected | S |
| 150 | `features/customer/feedback/widgets/trip_feedback_bottom_sheet.dart` | Customer/Employee | High | Low | no obvious fixed-width risk found (299 lines) | None expected | S |
| 151 | `features/driver/cancelled_trips_screen.dart` | Driver | High | Low | fixed widths >=300 at L357(900) (643 lines) | None expected | S |
| 152 | `features/driver/dashboard/presentation/screens/customer_driver_page.dart` | Driver | High | Low | no obvious fixed-width risk found (213 lines) | None expected | S |
| 153 | `features/driver/dashboard/presentation/screens/driver_dashboard_screen.dart` | Driver | High | Low | fixed widths >=300 at L1044(1920),1209(420),1452(420) (3995 lines) | None expected | S |
| 154 | `features/driver/dashboard/presentation/screens/driver_individual_trips.dart` | Driver | High | Low | fixed widths >=300 at L686(1920) (2945 lines) | None expected | S |
| 155 | `features/driver/dashboard/presentation/screens/driver_main_parent_screen.dart` | Driver | High | Low | has 1 MediaQuery/0 LayoutBuilder/0 isMobile checks (777 lines) | None expected | S |
| 156 | `features/driver/dashboard/presentation/screens/hrm_driver_management.dart` | Driver | High | Low | no obvious fixed-width risk found (1008 lines) | None expected | S |
| 157 | `features/driver/dashboard/presentation/screens/real_time_fleet_dashboard.dart` | Driver | High | Low | fixed widths >=300 at L335(1000) (2490 lines) | None expected | S |
| 158 | `features/driver/dashboard/presentation/screens/trip_map_navigation_screen.dart` | Driver | High | Low | has 4 MediaQuery/0 LayoutBuilder/0 isMobile checks (1001 lines) | None expected | S |
| 159 | `features/driver/dashboard/presentation/screens/trips_driver_page.dart` | Driver | High | Low | no obvious fixed-width risk found (148 lines) | None expected | S |
| 160 | `features/driver/dashboard/presentation/screens/vehicle_checklist.dart` | Driver | High | Low | fixed widths >=300 at L355(700) (715 lines) | None expected | S |
| 161 | `features/driver/screens/driver_live_trip_screen.dart` | Driver | High | Low | 9 Row() and no MediaQuery/LayoutBuilder/isMobile; 5 dialogs/sheets, none width-aware (983 lines) | None expected | S |
| 162 | `features/driver/trip_history/presentation/screens/driver_trip_history_screen.dart` | Driver | High | Low | no obvious fixed-width risk found (214 lines) | None expected | S |
| 163 | `features/driver/trip_history/presentation/screens/driver_trip_log_details_screen.dart` | Driver | High | Low | no obvious fixed-width risk found (145 lines) | None expected | S |
| 164 | `features/notifications/presentation/screens/screens/driver_trip_response.dart` | Notifications | High | Low | 5 dialogs/sheets, none width-aware (607 lines) | None expected | S |
| 165 | `features/notifications/presentation/screens/screens/driver_trip_response_screen.dart` | Notifications | High | Low | no obvious fixed-width risk found (387 lines) | None expected | S |
| 166 | `core/services/floating_notification_service.dart` | Core/Shared | Medium | Low | has 1 MediaQuery/0 LayoutBuilder/0 isMobile checks (267 lines) | None expected | S |
| 167 | `core/widgets/notification_badge.dart` | Core/Shared | Medium | Low | no obvious fixed-width risk found (331 lines) | None expected | S |
| 168 | `core/widgets/notification_overlay_widget.dart` | Core/Shared | Medium | Low | no obvious fixed-width risk found (400 lines) | None expected | S |
| 169 | `core/widgets/vehicle_logo_icon.dart` | Core/Shared | Medium | Low | no obvious fixed-width risk found (36 lines) | None expected | S |
| 170 | `features/admin/Billing/app_top_bar.dart` | Admin | Medium | Low | no obvious fixed-width risk found (78 lines) | None expected | S |
| 171 | `features/admin/Billing/create_rate_card.dart` | Admin | Medium | Low | has 0 MediaQuery/1 LayoutBuilder/5 isMobile checks (1157 lines) | None expected | S |
| 172 | `features/admin/Billing/pages/add_account_dialog.dart` | Admin | Medium | Low | fixed widths >=300 at L328(750) (1006 lines) | None expected | S |
| 173 | `features/admin/Billing/pages/banking_page.dart` | Admin | Medium | Low | fixed widths >=300 at L785(700),2097(500) (2297 lines) | None expected | S |
| 174 | `features/admin/Billing/pages/billing_page_template.dart` | Admin | Medium | Low | has 1 MediaQuery/0 LayoutBuilder/0 isMobile checks (180 lines) | None expected | S |
| 175 | `features/admin/Billing/pages/budget_detail.dart` | Admin | Medium | Low | DataTable/Table at L298,392 (510 lines) | None expected | S |
| 176 | `features/admin/Billing/pages/chart_of_account_detail.dart` | Admin | Medium | Low | DataTable/Table at L543 (806 lines) | None expected | S |
| 177 | `features/admin/Billing/pages/create_rate_card.dart` | Admin | Medium | Low | has 0 MediaQuery/1 LayoutBuilder/5 isMobile checks (1158 lines) | None expected | S |
| 178 | `features/admin/Billing/pages/expenses_list_page.dart` | Admin | Medium | Low | fixed widths >=300 at L349(500),1560(600) (1717 lines) | None expected | S |
| 179 | `features/admin/Billing/pages/home_billing.dart` | Admin | Medium | Low | has 1 MediaQuery/0 LayoutBuilder/0 isMobile checks (1750 lines) | None expected | S |
| 180 | `features/admin/Billing/pages/income_expense_report.dart` | Admin | Medium | Low | no obvious fixed-width risk found (669 lines) | None expected | S |
| 181 | `features/admin/Billing/pages/manual_journal_detail.dart` | Admin | Medium | Low | fixed widths >=300 at L532(600),771(560) (928 lines) | None expected | S |
| 182 | `features/admin/Billing/pages/new_bill.dart` | Admin | Medium | Low | fixed widths >=300 at L358(320),1405(500) (1612 lines) | None expected | S |
| 183 | `features/admin/Billing/pages/new_budget.dart` | Admin | Medium | Low | fixed widths >=300 at L255(300),851(480) (906 lines) | None expected | S |
| 184 | `features/admin/Billing/pages/new_chart_of_account.dart` | Admin | Medium | Low | has 0 MediaQuery/2 LayoutBuilder/0 isMobile checks (437 lines) | None expected | S |
| 185 | `features/admin/Billing/pages/new_credit_note.dart` | Admin | Medium | Low | fixed widths >=300 at L556(320),1616(500) (1757 lines) | None expected | S |
| 186 | `features/admin/Billing/pages/new_customer.dart` | Admin | Medium | Low | fixed widths >=300 at L474(600),1403(350) (3612 lines) | None expected | S |
| 187 | `features/admin/Billing/pages/new_delivery_challan.dart` | Admin | Medium | Low | fixed widths >=300 at L382(500),507(320) (1377 lines) | None expected | S |
| 188 | `features/admin/Billing/pages/new_expenses.dart` | Admin | Medium | Low | fixed widths >=300 at L671(320),1525(480) (2142 lines) | None expected | S |
| 189 | `features/admin/Billing/pages/new_invoice.dart` | Admin | Medium | Low | fixed widths >=300 at L231(1024),586(320),2048(500) (2238 lines) | None expected | S |
| 190 | `features/admin/Billing/pages/new_manual_journal.dart` | Admin | Medium | Low | fixed widths >=300 at L405(300),730(480),842(480) (1099 lines) | None expected | S |
| 191 | `features/admin/Billing/pages/new_payment_made.dart` | Admin | Medium | Low | fixed widths >=300 at L559(320),1656(480) (1807 lines) | None expected | S |
| 192 | `features/admin/Billing/pages/new_payment_page.dart` | Admin | Medium | Low | fixed widths >=300 at L376(320) (1440 lines) | None expected | S |
| 193 | `features/admin/Billing/pages/new_purchase_order.dart` | Admin | Medium | Low | fixed widths >=300 at L375(320),1289(500) (1524 lines) | None expected | S |
| 194 | `features/admin/Billing/pages/new_quote.dart` | Admin | Medium | Low | fixed widths >=300 at L416(350),1267(500) (1381 lines) | None expected | S |
| 195 | `features/admin/Billing/pages/new_recurring_bill.dart` | Admin | Medium | Low | fixed widths >=300 at L363(500),442(500),579(320) (1555 lines) | None expected | S |
| 196 | `features/admin/Billing/pages/new_recurring_expense.dart` | Admin | Medium | Low | fixed widths >=300 at L381(320),1231(500) (1535 lines) | None expected | S |
| 197 | `features/admin/Billing/pages/new_recurring_invoice.dart` | Admin | Medium | Low | fixed widths >=300 at L350(320),1547(500) (1679 lines) | None expected | S |
| 198 | `features/admin/Billing/pages/new_sales_order.dart` | Admin | Medium | Low | fixed widths >=300 at L401(320),752(600),1171(500) (1285 lines) | None expected | S |
| 199 | `features/admin/Billing/pages/new_vendor.dart` | Admin | Medium | Low | has 0 MediaQuery/8 LayoutBuilder/0 isMobile checks (1010 lines) | None expected | S |
| 200 | `features/admin/Billing/pages/new_vendor_credit.dart` | Admin | Medium | Low | fixed widths >=300 at L270(320),982(480) (1135 lines) | None expected | S |
| 201 | `features/admin/Billing/pages/payments_received_page.dart` | Admin | Medium | Low | DataTable/Table at L674 (865 lines) | None expected | S |
| 202 | `features/admin/Billing/pages/rate_card_detail_screen.dart` | Admin | Medium | Low | fixed widths >=300 at L281(500),332(500) (2420 lines) | None expected | S |
| 203 | `features/admin/Billing/pages/vendors_list_page.dart` | Admin | Medium | Low | fixed widths >=300 at L1961(600) (2246 lines) | None expected | S |
| 204 | `features/admin/admin_live_location_whole_vehicles.dart` | Admin | Medium | Low | fixed widths >=300 at L1026(300),1348(350) (2446 lines) | None expected | S |
| 205 | `features/admin/customer_management/admin_all_customers.dart` | Admin | Medium | Low | DataTable/Table at L1829 (2551 lines) | None expected | S |
| 206 | `features/admin/customer_management/admin_pending_customers.dart` | Admin | Medium | Low | DataTable/Table at L1536 (1992 lines) | None expected | S |
| 207 | `features/admin/customer_management/bulk_import_overlay.dart` | Admin | Medium | Low | DataTable/Table at L618,1467 (1666 lines) | None expected | S |
| 208 | `features/admin/customer_management/customer_form_overlay.dart` | Admin | Medium | Low | fixed widths >=300 at L159(600),160(450) (1254 lines) | None expected | S |
| 209 | `features/admin/customer_management/presentation/screens/admin_add_edit_customer_screen.dart` | Admin | Medium | Low | no obvious fixed-width risk found (398 lines) | None expected | S |
| 210 | `features/admin/customer_management/presentation/screens/admin_customer_details_screen.dart` | Admin | Medium | Low | no obvious fixed-width risk found (206 lines) | None expected | S |
| 211 | `features/admin/customer_management/presentation/screens/admin_customer_list_screen.dart` | Admin | Medium | Low | no obvious fixed-width risk found (348 lines) | None expected | S |
| 212 | `features/admin/customer_management/widgets/driver_buffer_dialog.dart` | Admin | Medium | Low | fixed widths >=300 at L113(440); 4 dialogs/sheets, none width-aware (189 lines) | None expected | S |
| 213 | `features/admin/customer_management/widgets/route_optimization_input_dialog.dart` | Admin | Medium | Low | no obvious fixed-width risk found (324 lines) | None expected | S |
| 214 | `features/admin/driver_admin_management/admin_vehicle_checklist_screen.dart` | Admin | Medium | Low | DataTable/Table at L523 (607 lines) | None expected | S |
| 215 | `features/admin/driver_admin_management/driver_admin_management_screen.dart` | Admin | Medium | Low | 12 Row() and no MediaQuery/LayoutBuilder/isMobile; 22 dialogs/sheets, none width-aware (1246 lines) | None expected | S |
| 216 | `features/admin/driver_admin_management/driver_list_page.dart` | Admin | Medium | Low | fixed widths >=300 at L756(400),1108(500),3285(1700) (3429 lines) | None expected | S |
| 217 | `features/admin/driver_admin_management/driver_list_page_new.dart` | Admin | Medium | Low | has 2 MediaQuery/0 LayoutBuilder/0 isMobile checks (579 lines) | None expected | S |
| 218 | `features/admin/driver_management/admin_pending_drivers.dart` | Admin | Medium | Low | DataTable/Table at L1537 (1993 lines) | None expected | S |
| 219 | `features/admin/feedback/admin_feedback_screen.dart` | Admin | Medium | Low | 3 dialogs/sheets, none width-aware (396 lines) | None expected | S |
| 220 | `features/admin/hrm/hrm_feedback.dart` | HRM (admin) | Medium | Low | Already responsive: 7 MediaQuery, 6 LayoutBuilder, 32 isMobile; loaded by client shell as the Feedback module. | Spot-check only | S |
| 221 | `features/admin/reports/presentation/screens/admin_reports_screen.dart` | Admin | Medium | Low | DataTable/Table at L4143 (4241 lines) | None expected | S |
| 222 | `features/admin/vehicle_admin_management/compliance management/compliance_management.dart` | Admin | Medium | Low | has 2 MediaQuery/1 LayoutBuilder/0 isMobile checks (882 lines) | None expected | S |
| 223 | `features/admin/vehicle_admin_management/fleet_vehicles_list_screen.dart` | Admin | Medium | Low | no obvious fixed-width risk found (542 lines) | None expected | S |
| 224 | `features/admin/vehicle_admin_management/maintainace_managemnt/cost_analysis.dart` | Admin | Medium | Low | no obvious fixed-width risk found (258 lines) | None expected | S |
| 225 | `features/admin/vehicle_admin_management/maintainace_managemnt/maintenance_reports.dart` | Admin | Medium | Low | DataTable/Table at L465 (513 lines) | None expected | S |
| 226 | `features/admin/vehicle_admin_management/maintainace_managemnt/schedule_maintenance.dart` | Admin | Medium | Low | 5 dialogs/sheets, none width-aware (1039 lines) | None expected | S |
| 227 | `features/admin/vehicle_admin_management/maintainace_managemnt/vendor_management.dart` | Admin | Medium | Low | DataTable/Table at L518 (608 lines) | None expected | S |
| 228 | `features/admin/vehicle_admin_management/reports_analytics/reports_analytics_screen.dart` | Admin | Medium | Low | has 2 MediaQuery/0 LayoutBuilder/0 isMobile checks (510 lines) | None expected | S |
| 229 | `features/admin/vehicle_admin_management/vehicle_master/add_vehicle.dart` | Admin | Medium | Low | has 1 MediaQuery/1 LayoutBuilder/0 isMobile checks (773 lines) | None expected | S |
| 230 | `features/admin/vehicle_admin_management/vehicle_master/bulk_import_vehicles.dart` | Admin | Medium | Low | DataTable/Table at L430,1005 (1131 lines) | None expected | S |
| 231 | `features/admin/vehicle_admin_management/vehicle_master/export_vehicles.dart` | Admin | Medium | Low | fixed widths >=300 at L430(400),506(500) (1277 lines) | None expected | S |
| 232 | `features/admin/vehicle_admin_management/vehicle_master/vehicle_master.dart` | Admin | Medium | Low | fixed widths >=300 at L1589(2100) (1910 lines) | None expected | S |
| 233 | `features/admin/vehicle_admin_management/vehicle_master/vehicle_master_redesigned_part2.dart` | Admin | Medium | Low | no obvious fixed-width risk found (320 lines) | None expected | S |
| 234 | `features/admin/vehicle_management/presentation/screens/vehicle_tracking_screen.dart` | Admin | Medium | Low | no obvious fixed-width risk found (190 lines) | None expected | S |
| 235 | `features/admin/vehicle_management/presentation/widgets/seat_capacity_indicator.dart` | Admin | Medium | Low | no obvious fixed-width risk found (346 lines) | None expected | S |
| 236 | `features/customer/feedback/screens/my_feedback_screen.dart` | Customer/Employee | Medium | Low | no obvious fixed-width risk found (219 lines) | None expected | S |
| 237 | `features/customer/history/presentation/screens/customer_booking_history_details_screen.dart` | Customer/Employee | Medium | Low | fixed widths >=300 at L82(800) (170 lines) | None expected | S |
| 238 | `features/customer/history/presentation/screens/customer_booking_history_screen.dart` | Customer/Employee | Medium | Low | fixed widths >=300 at L69(900) (161 lines) | None expected | S |
| 239 | `features/customer/profile/presentation/screens/customer_profile_screen.dart` | Customer/Employee | Medium | Low | no obvious fixed-width risk found (250 lines) | None expected | S |
| 240 | `features/customer/profile/presentation/screens/edit_customer_profile_screen.dart` | Customer/Employee | Medium | Low | no obvious fixed-width risk found (230 lines) | None expected | S |
| 241 | `features/customer/tracking/presentation/screens/customer_track_booking_screen.dart` | Customer/Employee | Medium | Low | fixed widths >=300 at L107(900) (292 lines) | None expected | S |
| 242 | `features/customer/widgets/customer_feedback_dialog.dart` | Customer/Employee | Medium | Low | fixed widths >=300 at L91(500) (303 lines) | None expected | S |
| 243 | `features/customer/widgets/enhanced_customer_widgets.dart` | Customer/Employee | Medium | Low | has 0 MediaQuery/1 LayoutBuilder/2 isMobile checks (758 lines) | None expected | S |
| 244 | `features/driver/profile/presentation/screens/driver_attendance_widget.dart` | Driver | Medium | Low | 14 Row() and no MediaQuery/LayoutBuilder/isMobile (894 lines) | None expected | S |
| 245 | `features/driver/profile/presentation/screens/driver_documents_screen.dart` | Driver | Medium | Low | fixed widths >=300 at L316(900); 5 dialogs/sheets, none width-aware (752 lines) | None expected | S |
| 246 | `features/driver/profile/presentation/screens/driver_profile_screen.dart` | Driver | Medium | Low | no obvious fixed-width risk found (600 lines) | None expected | S |
| 247 | `features/driver/profile/presentation/screens/edit_driver_profile_screen.dart` | Driver | Medium | Low | no obvious fixed-width risk found (205 lines) | None expected | S |
| 248 | `features/driver/screens/stop_otp_verification_screen.dart` | Driver | Medium | Low | fixed widths >=300 at L306(1200),333(1200) (1047 lines) | None expected | S |
| 249 | `features/fleet/vehicle_tracking/presentation/screens/vehicle_tracking_screen.dart` | Fleet | Medium | Low | 8 Row() and no MediaQuery/LayoutBuilder/isMobile (751 lines) | None expected | S |
| 250 | `features/hrm_feedback/presentation/screens/hrm_admin_client_feedback_screen.dart` | HRM feedback | Medium | Low | 9 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (807 lines) | None expected | S |
| 251 | `features/hrm_feedback/presentation/screens/hrm_admin_customer_feedback_screen.dart` | HRM feedback | Medium | Low | 9 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (807 lines) | None expected | S |
| 252 | `features/hrm_feedback/presentation/screens/hrm_admin_driver_feedback_screen.dart` | HRM feedback | Medium | Low | 10 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (909 lines) | None expected | S |
| 253 | `features/hrm_feedback/presentation/screens/hrm_attendance_screen.dart` | HRM feedback | Medium | Low | 8 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (547 lines) | None expected | S |
| 254 | `features/hrm_feedback/presentation/screens/hrm_leave_requests_screen.dart` | HRM feedback | Medium | Low | has 0 MediaQuery/2 LayoutBuilder/9 isMobile checks (1557 lines) | None expected | S |
| 255 | `features/hrm_feedback/presentation/screens/hrm_payroll_screen.dart` | HRM feedback | Medium | Low | has 0 MediaQuery/2 LayoutBuilder/9 isMobile checks (1385 lines) | None expected | S |
| 256 | `features/hrm_feedback/presentation/screens/hrm_portal_screen.dart` | HRM feedback | Medium | Low | no obvious fixed-width risk found (226 lines) | None expected | S |
| 257 | `features/hrm_feedback/presentation/screens/unified_feedback_management_screen.dart` | HRM feedback | Medium | Low | 14 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1184 lines) | None expected | S |
| 258 | `features/notifications/presentation/screens/admin_notifications_screen.dart` | Notifications | Medium | Low | 13 Row() and no MediaQuery/LayoutBuilder/isMobile; 7 dialogs/sheets, none width-aware (1209 lines) | None expected | S |
| 259 | `features/notifications/presentation/screens/client_notifications_screen.dart` | Notifications | Medium | Low | no obvious fixed-width risk found (875 lines) | None expected | S |
| 260 | `features/notifications/presentation/screens/driver_notifications_screen.dart` | Notifications | Medium | Low | 13 Row() and no MediaQuery/LayoutBuilder/isMobile; 4 dialogs/sheets, none width-aware (1595 lines) | None expected | S |
| 261 | `features/notifications/presentation/screens/notifications_screen.dart` | Notifications | Medium | Low | 9 Row() and no MediaQuery/LayoutBuilder/isMobile; 8 dialogs/sheets, none width-aware (1154 lines) | None expected | S |
| 262 | `features/settings/notification_settings_screen.dart` | Settings | Medium | Low | no obvious fixed-width risk found (314 lines) | None expected | S |
| 263 | `app/presentation/screens/main_app_shell.dart` | Core/Shared | Low | Low | no obvious fixed-width risk found (438 lines) | None expected | S |
| 264 | `core/services/error_handler_service.dart` | Core/Shared | Low | Low | no obvious fixed-width risk found (339 lines) | None expected | S |
| 265 | `core/widgets/app_error_dialog.dart` | Core/Shared | Low | Low | fixed widths >=300 at L191(400); 3 dialogs/sheets, none width-aware (470 lines) | None expected | S |
| 266 | `core/widgets/fleet_map_widget.dart` | Core/Shared | Low | Low | no obvious fixed-width risk found (542 lines) | None expected | S |
| 267 | `core/widgets/permission_restricted_dialog.dart` | Core/Shared | Low | Low | fixed widths >=300 at L56(440); 3 dialogs/sheets, none width-aware (161 lines) | None expected | S |
| 268 | `features/TMS/all_tickets.dart` | Tickets (TMS) | Low | Low | fixed widths >=300 at L393(600),1019(1540),1328(700) (1778 lines) | None expected | S |
| 269 | `features/TMS/closed_tickets.dart` | Tickets (TMS) | Low | Low | DataTable/Table at L869 (1362 lines) | None expected | S |
| 270 | `features/TMS/my_tickets.dart` | Tickets (TMS) | Low | Low | fixed widths >=300 at L495(600),1460(700) (1934 lines) | None expected | S |
| 271 | `features/TMS/raise_ticket.dart` | Tickets (TMS) | Low | Low | 10 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (1115 lines) | None expected | S |
| 272 | `features/TMS/tickets_webview_screen.dart` | Tickets (TMS) | Low | Low | no obvious fixed-width risk found (289 lines) | None expected | S |
| 273 | `features/admin/ERP/app_top_bar.dart` | Admin | Low | Low | no obvious fixed-width risk found (78 lines) | None expected | S |
| 274 | `features/admin/ERP/permission.dart` | Admin | Low | Low | 9 Row() and no MediaQuery/LayoutBuilder/isMobile (1071 lines) | None expected | S |
| 275 | `features/admin/client_management/add_client_admin.dart` | Admin | Low | Low | fixed widths >=300 at L151(400) (1075 lines) | None expected | S |
| 276 | `features/admin/client_management/edit_client_admin.dart` | Admin | Low | Low | 8 Row() and no MediaQuery/LayoutBuilder/isMobile; 3 dialogs/sheets, none width-aware (799 lines) | None expected | S |
| 277 | `features/admin/hrm/hrm_employee_filters.dart` | HRM (admin) | Low | Low | no obvious fixed-width risk found (1297 lines) | None expected | S |
| 278 | `features/admin/maintenance_management/presentation/screens/admin_add_edit_maintenance_task_screen.dart` | Admin | Low | Low | no obvious fixed-width risk found (396 lines) | None expected | S |
| 279 | `features/admin/maintenance_management/presentation/screens/admin_maintenance_log_screen.dart` | Admin | Low | Low | no obvious fixed-width risk found (383 lines) | None expected | S |
| 280 | `features/admin/maintenance_management/presentation/screens/admin_maintenance_task_details_screen.dart` | Admin | Low | Low | no obvious fixed-width risk found (290 lines) | None expected | S |
| 281 | `features/admin/map_view/presentation/screens/admin_map_view_screen.dart` | Admin | Low | Low | no obvious fixed-width risk found (84 lines) | None expected | S |
| 282 | `features/admin/otp_monitoring/otp_failed_log_screen.dart` | Admin | Low | Low | has 2 MediaQuery/0 LayoutBuilder/0 isMobile checks (723 lines) | None expected | S |
| 283 | `features/admin/otp_monitoring/otp_live_monitor_screen.dart` | Admin | Low | Low | fixed widths >=300 at L164(900) (246 lines) | None expected | S |
| 284 | `features/admin/otp_monitoring/otp_override_approval_screen.dart` | Admin | Low | Low | has 1 MediaQuery/0 LayoutBuilder/0 isMobile checks (499 lines) | None expected | S |
| 285 | `features/admin/settings/presentation/screens/admin_settings_screen.dart` | Admin | Low | Low | no obvious fixed-width risk found (185 lines) | None expected | S |
| 286 | `features/admin/user_management/presentation/screens/create_user_screen.dart` | Admin | Low | Low | 4 dialogs/sheets, none width-aware (394 lines) | None expected | S |
| 287 | `features/admin/user_management/presentation/screens/user_management_screen.dart` | Admin | Low | Low | no obvious fixed-width risk found (307 lines) | None expected | S |
| 288 | `features/admin/widgets/country_state_city_filter.dart` | Admin | Low | Low | no obvious fixed-width risk found (872 lines) | None expected | S |
| 289 | `features/auth/presentation/screens/forgot_password_screen.dart` | Auth | Low | Low | has 1 MediaQuery/0 LayoutBuilder/0 isMobile checks (363 lines) | None expected | S |
| 290 | `features/auth/presentation/screens/splash_screen.dart` | Auth | Low | Low | no obvious fixed-width risk found (118 lines) | None expected | S |
| 291 | `features/auth/presentation/screens/welcome_screen.dart` | Auth | Low | Low | fixed widths >=300 at L305(1100),652(980) (1078 lines) | None expected | S |
| 292 | `features/support/support_system_screen.dart` | Support | Low | Low | no obvious fixed-width risk found (282 lines) | None expected | S |
| 293 | `features/testing/backend_test_screen.dart` | Testing | Low | Low | no obvious fixed-width risk found (214 lines) | None expected | S |
| 294 | `features/testing/connection_test_screen.dart` | Testing | Low | Low | 4 dialogs/sheets, none width-aware (319 lines) | None expected | S |
| 295 | `features/tours_travels/tours_travels_webview_screen.dart` | Tours & Travels | Low | Low | no obvious fixed-width risk found (349 lines) | None expected | S |
| 296 | `features/tracking/screens/map_widget_mobile.dart` | Tracking | Low | Low | no obvious fixed-width risk found (251 lines) | None expected | S |
| 297 | `features/tracking/screens/map_widget_stub.dart` | Tracking | Low | Low | no obvious fixed-width risk found (24 lines) | None expected | S |
| 298 | `features/tracking/screens/tracking_screen.dart` | Tracking | Low | Low | no obvious fixed-width risk found (444 lines) | None expected | S |
| 299 | `features/websocket_example/websocket_example_screen.dart` | Example | Low | Low | no obvious fixed-width risk found (229 lines) | None expected | S |
| 300 | `main.dart` | Other | Low | Low | has 2 MediaQuery/0 LayoutBuilder/0 isMobile checks (1017 lines) | None expected | S |
| 301 | `test_connection_main.dart` | Other | Low | Low | no obvious fixed-width risk found (47 lines) | None expected | S |

**Non-UI files (no screen, nothing to fix), by folder:**

- `lib`: 5 files
- `app/config`: 3 files
- `app/config/theme`: 2 files
- `app/navigation`: 1 files
- `app/utils`: 3 files
- `app/widgets`: 2 files
- `core/exceptions`: 1 files
- `core/models`: 4 files
- `core/providers`: 2 files
- `core/services`: 96 files
- `core/utils`: 7 files
- `data/datasources/remote`: 1 files
- `data/models`: 3 files
- `data/repositories`: 1 files
- `features/TMS`: 1 files
- `features/admin/Billing/pages`: 1 files
- `features/admin/ERP`: 1 files
- `features/admin/client_management/models`: 1 files
- `features/admin/client_management/services`: 1 files
- `features/admin/customer_management/domain/entities`: 1 files
- `features/admin/customer_management/domain/repositories`: 1 files
- `features/admin/customer_management/notification`: 1 files
- `features/admin/customer_management/presentation/providers`: 1 files
- `features/admin/dashboard/presentation/screens`: 1 files
- `features/admin/driver_admin_management`: 1 files
- `features/admin/driver_management/data/repositories`: 1 files
- `features/admin/driver_management/domain/entities`: 1 files
- `features/admin/driver_management/domain/repositories`: 1 files
- `features/admin/driver_management/presentation/providers`: 1 files
- `features/admin/maintenance_management/data/repositories`: 1 files
- `features/admin/maintenance_management/domain/entities`: 1 files
- `features/admin/maintenance_management/domain/repositories`: 2 files
- `features/admin/maintenance_management/presentation/providers`: 1 files
- `features/admin/services`: 1 files
- `features/admin/tms/presentation/screens`: 1 files
- `features/admin/vehicle_admin_management/vehicle_master`: 5 files
- `features/admin/vehicle_management/data/repositories`: 2 files
- `features/admin/vehicle_management/domain/entities`: 1 files
- `features/admin/vehicle_management/domain/repositories`: 1 files
- `features/admin/vehicle_management/presentation/providers`: 2 files
- `features/auth/data/repositories`: 3 files
- `features/auth/domain/entities`: 1 files
- `features/auth/domain/repositories`: 1 files
- `features/customer/booking/data/repositories`: 1 files
- `features/customer/booking/domain/entities`: 1 files
- `features/customer/booking/domain/repositories`: 1 files
- `features/customer/booking/presentation/providers`: 1 files
- `features/customer/dashboard/data/repositories`: 1 files
- `features/customer/dashboard/data/services`: 1 files
- `features/customer/history/data/repositories`: 1 files
- `features/customer/history/domain/entities`: 1 files
- `features/customer/history/domain/repositories`: 1 files
- `features/customer/history/presentation/providers`: 1 files
- `features/driver/dashboard/presentation/screens`: 2 files
- `features/driver/profile/presentation/screens`: 1 files
- `features/driver/trip_history/data/repositories`: 1 files
- `features/driver/trip_history/domain/entities`: 1 files
- `features/driver/trip_history/domain/repositories`: 1 files
- `features/driver/trip_history/presentation/providers`: 1 files
- `features/driver/trip_reporting/presentation/screens`: 2 files
- `features/hrm_feedback/domain/models`: 1 files
- `features/notifications/data/repositories`: 2 files
- `features/notifications/domain/entities`: 1 files
- `features/notifications/domain/repositories`: 1 files
- `features/notifications/presentation/providers`: 1 files
- `features/tours_travels`: 2 files

## 3. Repeated patterns that should become shared phone helpers

Suggested home: a new `lib/core/widgets/responsive/` folder (or `lib/core/utils/responsive.dart`). Create these first, in the first fix batch, so later batches reuse them. Each must be a no-op at width >= 768 so desktop and tablet stay unchanged.

| Helper | Problem it solves | Where it appears most |
|---|---|---|
| `Breakpoints` / `context.isPhone` (width < 600) and `isCompact` (< 768) | Every screen hand-rolls `MediaQuery.of(context).size.width < 768` | everywhere; `client_main_shell.dart`, `client_dashboard_analytics.dart`, `hrm_feedback.dart` use it already |
| `PhoneHeaderRow` (title + optional badge + actions; actions wrap below the title or collapse to icons/overflow menu on phone) | Title Row with 2-4 action buttons runs off the right edge | `client_employee_management.dart` (L348), `client_dashboard_analytics.dart` (L451), `client_sos_alerts.dart` (L383, 2099), `client_all_trips.dart` (New Trip/Export row L740-800), admin screens |
| `MapSidePanelToSheet` (side panel on desktop, DraggableScrollableSheet or modal bottom sheet on phone) | Fixed 300/350 px list and details panels over a map | `client_based_all_vehicles.dart` (L836, 1276), `admin/vehicle_admin_management/enhanced_fleet_map_screen.dart` (L576 width 350), `admin/admin_live_location_whole_vehicles.dart`, `fleet/vehicle_tracking` |
| `ScrollableTabs` (TabBar with `isScrollable: true`, `tabAlignment: start`, short labels) | Fixed 2-4 tab bars clip labels ("Rost...") | `client_reports_analytics_enhanced.dart`, `client_billing_invoices.dart` (L1028), `client_sos_alerts.dart` (L411), `client_feedback_management.dart` (L233), `admin/hrm/hrm_master_settings_screen.dart`, `admin/Billing/rate_card_list.dart` |
| `ResponsiveTable<T>` (DataTable/wide table above 768, card list below 600 with the same data and tap handler) | Tables of 10-19 fixed-width columns | `client_trip_dashboard_part2.dart` (19 columns, ~2400 px), `client_all_trips.dart` (L1007, ~1530 px), `client_employee_management.dart` (1340 px), `bulk_import_rosters.dart`, `admin/hrm/hrm_employee_list.dart`, `vehicle_master_redesigned_part3.dart` (1310 px), TMS ticket lists |
| `PhoneFilterBar` (search full width + "Filters" button opening a bottom sheet; desktop keeps the inline row) | Sticky filter rows, From/To/Country dropdowns hidden sideways; fixed 220 px search | `client_all_trips.dart` (L689, 1572+), `client_trip_dashboard_part1.dart` (L880), `admin/widgets/horizontal_filter_bar.dart` |
| `FitText` (money/number Text in FittedBox scaleDown or ellipsis) | Money cells in spaceBetween Rows | `client_billing_invoices.dart` (L2139-2229), admin Billing pages |
| `phoneDialogWidth(context)` / `PhoneDialog` (width = min(screen - 32, desired), scrollable content, optional bottom sheet) | AlertDialogs with unconstrained or fixed 500-900 px content | `client_employee_management.dart`, `client_all_trips.dart`, `client_sos_alerts.dart`, `admin/Billing/**` (900, 650, 600 widths), `core/widgets/app_error_dialog.dart`, admin roster dialogs |
| `AdaptiveGrid` (crossAxisCount by width: 1-2 phone, 3 tablet, 4+ desktop; no fixed height holding text) | Stat/summary grids with fixed counts and fixed 100-220 px chart cards | `client_reports_analytics_enhanced.dart` (L1571, 160 px cards), `client_dashboard.dart`, `client_billing_invoices.dart` (L2056) |
| `LabelValueRow` (label Flexible + value Flexible with ellipsis) | `Row(spaceBetween, [Text, Text])` overflow on long names | `client_trip_details.dart` (L1277-1616), profile pages, admin detail pages |

## 4. Proposed fix batches (3-4 screens each, highest use and severity first)

Each session must only change phone behavior (width < 600/768) and keep desktop unchanged. Batch 1 also creates the shared helpers.

| Batch | Files | Why |
|---|---|---|
| **1 (client, helpers + observed bugs)** | `lib/features/client/client_employee_management.dart`, `client_dashboard_analytics.dart` (+ quick check of `client_dashboard.dart`), `client_based_all_vehicles.dart`, `client_all_trips.dart` (+ create `lib/core/widgets/responsive/*`) | the problems the user saw; highest use; creates `PhoneHeaderRow`, `MapSidePanelToSheet`, `PhoneFilterBar`, `phoneDialogWidth` |
| **2 (client, trips and reports)** | `client_trip_dashboard_part1.dart`, `client_trip_dashboard_part2.dart`, `client_trip_details.dart`, `client_reports_analytics_enhanced.dart` | 19-column trip table to card list, filters, tab strip, summary cards |
| **3 (client, SOS, rosters, import)** | `client_sos_alerts.dart`, `bulk_import_rosters.dart`, `client_roster_management.dart` (+ `client_pending_assignment_tab.dart`), `start_client_trip.dart` | fixed 500 height, import preview, dialog widths |
| **4 (client, remainder)** | `client_profile_page.dart`, `client_main_shell.dart` (bottom-nav / dialog checks only), `client_billing_invoices.dart`, `client_feedback_management.dart` (+ orphans `leave_request_management.dart`, `organization_shift_config_screen.dart`: skip unless wired in) | low use / low severity |
| 5 (auth + customer/employee) | `auth/presentation/screens/login_screen.dart`, `registration_screen.dart`, `customer/dashboard/presentation/screens/my_trips_screen.dart`, `location_picker_screen.dart` | login and the employee app are phone-first |
| 6 (driver) | `driver/screens/driver_live_trip_screen.dart`, `driver/dashboard/presentation/screens/reports_driver_page.dart`, `profile_driver_page.dart`, `driver/profile/presentation/screens/driver_attendance_widget.dart` | drivers use phones all day |
| 7 (notifications + customer lists) | `notifications/presentation/screens/customer_notifications_screen.dart`, `driver_notifications_screen.dart`, `admin_notifications_screen.dart`, `customer/dashboard/presentation/screens/my_address_requests_screen.dart` | list screens, mostly Row fixes |
| 8 (HRM and feedback) | `admin/hrm/hrm_employees_screen.dart`, `hrm_employee_list.dart`, `hrm_master_settings_screen.dart`, `hrm_feedback/presentation/screens/hrm_admin_feedback_screen.dart` | wide tables |
| 9 (admin trips and map) | `admin/admin_trip_details.dart`, `admin/vehicle_admin_management/enhanced_fleet_map_screen.dart`, `trip_operations/trip_analytics_screen.dart`, `admin/dashboard/presentation/screens/incomplete_sos_alerts_screen.dart` | admin is mostly desktop |
| 10-12 (admin Billing, TMS) | `admin/Billing/pages/reconciliation_billing.dart` (5136 lines, L), `recurring_expenses_list_page.dart`, `import_transactions_dialog.dart`, `rate_card_list.dart`; then TMS `raise_ticket.dart`, `ticket_detail_screen.dart`, `all_tickets*.dart` | desktop-first accounting screens, do last |

The remaining Medium rows of section 2 can be spot-checked in groups by folder after batch 9.

## 5. Things I could not verify

- **No visual check.** I did not open the running app (http://localhost:51212 needs a login and I must not enter credentials). Everything is from reading code; overflow errors are inferred from Row/width structure, not seen.
- Non-client severities come from a regex heuristic: a High may be fine (a Row of short Expanded children) and a Medium may hide a real overflow. The Use column is a guess from file names.
- An `isMobile` flag passed down from a parent is counted only in the file that declares it, so a responsive child can be rated too harshly.
- Whether `leave_request_management`, `organization_shift_config_screen`, `client_billing_invoices` (BillingInvoicesPage) and `client_feedback_management` are reachable through named routes or dynamic loading: grep found no import or class reference, so I treated them as orphans.
- About 54 files are modified in the working tree by other sessions; some may have changed since I read them. Re-grep before starting each batch.
- `all_tickets_IMPROVED.dart` / `all_tickets_UPDATED.dart` look like superseded variants of `all_tickets.dart`; I did not check which one is routed.
- Large text scale (accessibility) and landscape phone were not considered.

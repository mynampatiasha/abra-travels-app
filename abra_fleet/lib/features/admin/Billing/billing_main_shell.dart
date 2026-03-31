import 'package:flutter/material.dart';
import 'pages/home_billing.dart';
import 'pages/items_billing.dart';
import 'pages/invoices_list_page.dart';
import 'pages/payments_received_page.dart';
import 'pages/customers_list_page.dart';
import 'pages/recurring_invoices_list_page.dart';
import 'pages/new_recurring_invoice.dart';
import 'pages/banking_page.dart'; // BankingDashboardPage
import 'pages/new_expenses.dart';
import 'pages/expenses_list_page.dart';
import 'pages/vendors_list_page.dart'; // Add vendors list page
import 'pages/quotes_list_page.dart'; // Add quotes list page
import 'pages/sales_orders_list_page.dart'; // Add sales orders list page
import 'pages/recurring_expenses_list_page.dart'; // Add recurring expenses list page
import 'pages/delivery_challans_list_page.dart'; // Add delivery challans list page
import 'pages/credit_notes_list_page.dart'; // Add credit notes list page
import 'pages/purchase_orders_list_page.dart'; // Add purchase orders list page
import 'pages/bill_list_page.dart'; // Add bills list page
import 'pages/recurring_bills_list_page.dart'; // Add recurring bills list page
import 'pages/payment_made_list_page.dart'; // Add payments made list page
import 'pages/vendor_credits_list_page.dart'; // Add vendor credits list page
import 'pages/manual_journals_list_page.dart'; // Add manual journals list page
import 'rate_card_list.dart'; // Add rate cards list page
import 'pages/chart_of_accounts_list_page.dart'; // Add chart of accounts list page
import 'pages/budgets_list_page.dart'; // Add budgets list page

// ─── COLORS ───────────────────────────────────────────────────────────────────
const _kNavyDark   = Color(0xFF0F172A); // darker navy for gradient start
const _kNavy       = Color(0xFF1E3A5F); // navy blue for gradient end
const _kBlueAccent = Color(0xFF2563EB); // active item highlight
const _kWhite      = Color(0xFFFFFFFF); // ALL TEXT - FULL WHITE
const _kPageBg     = Color(0xFFF8FAFC); // main content background
// ──────────────────────────────────────────────────────────────────────────────

class BillingMainShell extends StatefulWidget {
  const BillingMainShell({Key? key}) : super(key: key);

  @override
  State<BillingMainShell> createState() => _BillingMainShellState();
}

class _BillingMainShellState extends State<BillingMainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;

  // ── CHANGED: tracks current page title for the top bar ──
  String _currentPageTitle = 'Dashboard';

  // Track which sections are expanded
  final Map<String, bool> _expandedSections = {
    'accountant': false,
    'time_tracking': false,
    'purchases': false,
    'sales': false,
  };

  // Navigation items with hierarchical structure
  final List<NavigationItem> _mainMenuItems = [
    NavigationItem(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Dashboard',
      route: 'home',
    ),
    NavigationItem(
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      label: 'Items',
      route: 'items',
    ),
    NavigationItem(
      icon: Icons.shopping_cart_outlined,
      selectedIcon: Icons.shopping_cart,
      label: 'Sales',
      route: 'sales',
      isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Customers', route: 'sales/customers', icon: Icons.people_outline),
        SubNavigationItem(label: 'Invoices', route: 'sales/invoices', icon: Icons.receipt_long_outlined),
        SubNavigationItem(label: 'Recurring Invoices', route: 'sales/recurring_invoices', icon: Icons.repeat_outlined),
        SubNavigationItem(label: 'Payments Received', route: 'sales/payments_received', icon: Icons.payment_outlined),
        SubNavigationItem(label: 'Credit Notes', route: 'sales/credit_notes', icon: Icons.note_outlined),
        SubNavigationItem(label: 'Quotes', route: 'sales/quotes', icon: Icons.request_quote_outlined),
        SubNavigationItem(label: 'Sales Orders', route: 'sales/orders', icon: Icons.shopping_bag_outlined),
        SubNavigationItem(label: 'Delivery Challans', route: 'sales/delivery_challans', icon: Icons.local_shipping_outlined),
      ],
    ),
    NavigationItem(
      icon: Icons.shopping_bag_outlined,
      selectedIcon: Icons.shopping_bag,
      label: 'Purchases',
      route: 'purchases',
      isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Vendors', route: 'purchases/vendors', icon: Icons.store_outlined),
        SubNavigationItem(label: 'Expenses', route: 'purchases/expenses', icon: Icons.money_off_outlined),
        SubNavigationItem(label: 'Recurring Expenses', route: 'purchases/recurring_expenses', icon: Icons.repeat_outlined),
        SubNavigationItem(label: 'Purchase Orders', route: 'purchases/orders', icon: Icons.shopping_cart_outlined),
        SubNavigationItem(label: 'Bills', route: 'purchases/bills', icon: Icons.description_outlined),
        SubNavigationItem(label: 'Recurring Bills', route: 'purchases/recurring_bills', icon: Icons.repeat_outlined),
        SubNavigationItem(label: 'Payments Made', route: 'purchases/payments_made', icon: Icons.payment_outlined),
        SubNavigationItem(label: 'Vendor Credits', route: 'purchases/vendor_credits', icon: Icons.credit_card_outlined),
      ],
    ),
    NavigationItem(
      icon: Icons.access_time_outlined,
      selectedIcon: Icons.access_time,
      label: 'Time Tracking',
      route: 'time_tracking',
      isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Projects', route: 'time_tracking/projects', icon: Icons.folder_outlined),
        SubNavigationItem(label: 'Timesheet', route: 'time_tracking/timesheet', icon: Icons.schedule_outlined),
      ],
    ),
    NavigationItem(
      icon: Icons.credit_card_outlined,
      selectedIcon: Icons.credit_card,
      label: 'Rate Cards',
      route: 'rate_cards',
    ),
    
    NavigationItem(
      icon: Icons.account_balance_outlined,
      selectedIcon: Icons.account_balance,
      label: 'Banking',
      route: 'banking',
    ),
    NavigationItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Accountant',
      route: 'accountant',
      isExpandable: true,
      subItems: [
        SubNavigationItem(label: 'Manual Journals', route: 'accountant/manual_journals', icon: Icons.book_outlined),
        SubNavigationItem(label: 'Currency Adjustments', route: 'accountant/currency_adjustments', icon: Icons.currency_exchange_outlined),
        SubNavigationItem(label: 'Chart of Accounts', route: 'accountant/chart_of_accounts', icon: Icons.account_tree_outlined),
        SubNavigationItem(label: 'Budgets', route: 'accountant/budgets', icon: Icons.account_balance_wallet_outlined),
      ],
    ),
    NavigationItem(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'Reports',
      route: 'reports',
    ),
    NavigationItem(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder,
      label: 'Documents',
      route: 'documents',
    ),
  ];



  Widget _getSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return const HomeBilling();
      case 1:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ItemsBilling()),
            ).then((_) {
              setState(() {
                _selectedIndex = 0;
                _currentPageTitle = 'Dashboard'; // CHANGED: reset title
              });
            });
          }
        });
        return const HomeBilling();
      case 2:
        return _buildPlaceholderPage('Sales');
      case 3:
        return _buildPlaceholderPage('Purchases');
      case 4:
        return _buildPlaceholderPage('Time Tracking');
      case 5:
        // Rate Cards page - navigate to separate page
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RateCardListScreen(),
              ),
            ).then((_) {
              // Reset to home after returning from rate cards page
              setState(() {
                _selectedIndex = 0;
                _currentPageTitle = 'Dashboard';
              });
            });
          }
        });
        return const HomeBilling();
      case 6:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => BankingDashboardPage()),
            ).then((_) {
              setState(() {
                _selectedIndex = 0;
                _currentPageTitle = 'Dashboard'; // CHANGED: reset title
              });
            });
          }
        });
        return const HomeBilling();
      case 7:
        return _buildPlaceholderPage('Accountant');
      case 8:
        return _buildPlaceholderPage('Reports');
      case 9:
        return _buildPlaceholderPage('Documents');
      default:
        return const HomeBilling();
    }
  }

  Widget _buildPlaceholderPage(String title) {
    return Container(
      color: _kPageBg, // CHANGED: off-white background
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '$title Page',
              style: TextStyle(fontSize: 24, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Coming Soon',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            if (title == 'Sales' ||
                title == 'Purchases' ||
                title == 'Time Tracking' ||
                title == 'Accountant') ...[
              Text(
                'Click on "$title" in the sidebar to expand and see sub-items',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 1024;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isMobile ? _buildDrawer() : null,
      body: Row(
        children: [
          // ── Sidebar ────────────────────────────────────────────────────────
          if (!isMobile)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isSidebarExpanded ? 240 : 70,
              child: Container(
                // Navy blue gradient background
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_kNavyDark, _kNavy],
                  ),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      height: 70,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withOpacity(0.08),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _kBlueAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet,
                              color: _kWhite,
                              size: 24,
                            ),
                          ),
                          if (_isSidebarExpanded) ...[
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Finance Module',
                                style: TextStyle(
                                  color: _kWhite, // CHANGED: white text
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          IconButton(
                            icon: Icon(
                              _isSidebarExpanded
                                  ? Icons.chevron_left
                                  : Icons.chevron_right,
                              color: _kWhite, // FULL WHITE
                            ),
                            onPressed: () {
                              setState(() {
                                _isSidebarExpanded = !_isSidebarExpanded;
                              });
                            },
                            tooltip:
                                _isSidebarExpanded ? 'Collapse' : 'Expand',
                          ),
                        ],
                      ),
                    ),

                    // Menu items
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        children: [
                          ..._buildExpandableMenuItems(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Main content ───────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── CHANGED: Top bar — navy gradient, white text, dynamic title ──
                Container(
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [_kNavyDark, _kNavy],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      if (isMobile)
                        IconButton(
                          icon: const Icon(Icons.menu, color: _kWhite),
                          onPressed: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                          tooltip: 'Open Menu',
                        ),
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: _kWhite),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Back to Dashboard',
                      ),
                      const SizedBox(width: 12),
                      // CHANGED: shows current page name dynamically
                      Text(
                        _currentPageTitle,
                        style: const TextStyle(
                          color: _kWhite,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Page content
                Expanded(
                  child: Container(
                    color: _kPageBg, // CHANGED: off-white content bg
                    child: _getSelectedPage(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildExpandableMenuItems() {
    List<Widget> widgets = [];
    for (int index = 0; index < _mainMenuItems.length; index++) {
      final item = _mainMenuItems[index];
      widgets.add(_buildSidebarItem(item, index, _selectedIndex == index));
      if (item.isExpandable &&
          _expandedSections[item.route] == true &&
          _isSidebarExpanded) {
        for (final subItem in item.subItems ?? []) {
          widgets.add(_buildSubSidebarItem(subItem));
        }
      }
    }
    return widgets;
  }

  // ── CHANGED: white/slate text on navy ─────────────────────────────────────
  Widget _buildSubSidebarItem(SubNavigationItem subItem) {
    return InkWell(
      onTap: () {
        setState(() {
          _currentPageTitle = subItem.label; // CHANGED: update top bar title
        });
        _navigateToSubPage(subItem.route, subItem.label);
      },
      child: Container(
        margin: const EdgeInsets.only(left: 24, right: 12, top: 2, bottom: 2),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Show icon if available, otherwise show dot
              if (subItem.icon != null)
                Icon(
                  subItem.icon,
                  color: _kWhite, // FULL WHITE
                  size: 18,
                )
              else
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: _kWhite, // FULL WHITE
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  subItem.label,
                  style: const TextStyle(
                    color: _kWhite, // FULL WHITE
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToSubPage(String route, String label) {
    switch (route) {
      case 'sales/customers':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const CustomersListPage()));
        break;
      case 'sales/invoices':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const InvoicesListPage()));
        break;
      case 'sales/recurring_invoices':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const RecurringInvoicesListPage()));
        break;
      case 'sales/payments_received':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const PaymentsReceivedPage()));
        break;
      case 'sales/credit_notes':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const CreditNotesListPage()));
        break;
      case 'sales/quotes':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const QuotesListPage()));
        break;
      case 'sales/orders':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const SalesOrdersListPage()));
        break;
      case 'sales/delivery_challans':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const DeliveryChallansListPage()));
        break;
      case 'purchases/vendors':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const VendorsListPage()));
        break;
      case 'purchases/expenses':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const ExpensesListPage()));
        break;
      case 'purchases/recurring_expenses':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const RecurringExpensesListPage()));
        break;
      case 'purchases/orders':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const PurchaseOrdersListPage()));
        break;
      case 'purchases/bills':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const BillListPage()));
        break;
      case 'purchases/recurring_bills':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => RecurringBillsListPage()));
        break;
      case 'purchases/payments_made':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const PaymentMadeListPage()));
        break;
      case 'purchases/vendor_credits':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const VendorCreditsListPage()));
        break;
      case 'accountant/manual_journals':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const ManualJournalsListPage()));
        break;
      case 'accountant/chart_of_accounts':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const ChartOfAccountsListPage()));
        break;
      case 'accountant/budgets':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const BudgetsListPage()));
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Navigating to $label - Coming Soon'),
            duration: const Duration(seconds: 1),
            backgroundColor: _kBlueAccent,
          ),
        );
    }
  }

  // ── CHANGED: white/slate text on navy ─────────────────────────────────────
  Widget _buildSidebarItem(NavigationItem item, int index, bool isSelected) {
    final isExpandable = item.isExpandable;
    final isExpanded = _expandedSections[item.route] ?? false;

    return InkWell(
      onTap: () {
        if (isExpandable) {
          setState(() {
            _expandedSections[item.route] = !isExpanded;
          });
        } else if (index >= 0) {
          setState(() {
            _selectedIndex = index;
            _currentPageTitle = item.label; // CHANGED: update top bar title
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? _kBlueAccent // CHANGED: blue highlight when active
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                isSelected ? item.selectedIcon : item.icon,
                color: _kWhite, // FULL WHITE for all icons
                size: 24, // Increased size for better visibility
              ),
              if (_isSidebarExpanded) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: _kWhite, // FULL WHITE for all text
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w700 // BOLD when selected
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (isExpandable)
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: _kWhite, // FULL WHITE
                    size: 20,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Drawer (mobile) ───────────────────────────────────────────────────────
  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_kNavyDark, _kNavy],
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: Colors.white.withOpacity(0.08), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kBlueAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.account_balance_wallet,
                        color: _kWhite, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Finance Module',
                      style: TextStyle(
                        color: _kWhite, // CHANGED
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  ..._buildExpandableMenuItemsForDrawer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildExpandableMenuItemsForDrawer() {
    List<Widget> widgets = [];
    for (int index = 0; index < _mainMenuItems.length; index++) {
      final item = _mainMenuItems[index];
      widgets.add(_buildDrawerItem(item, index, _selectedIndex == index));
      if (item.isExpandable && _expandedSections[item.route] == true) {
        for (final subItem in item.subItems ?? []) {
          widgets.add(_buildSubDrawerItem(subItem));
        }
      }
    }
    return widgets;
  }

  Widget _buildDrawerItem(NavigationItem item, int index, bool isSelected) {
    final isExpandable = item.isExpandable;
    final isExpanded = _expandedSections[item.route] ?? false;

    return InkWell(
      onTap: () {
        if (isExpandable) {
          setState(() {
            _expandedSections[item.route] = !isExpanded;
          });
        } else {
          if (index >= 0) {
            setState(() {
              _selectedIndex = index;
              _currentPageTitle = item.label; // CHANGED: update top bar title
            });
          }
          Navigator.pop(context);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? _kBlueAccent : Colors.transparent, // CHANGED
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                isSelected ? item.selectedIcon : item.icon,
                color: _kWhite, // FULL WHITE for all icons
                size: 24, // Increased size
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: _kWhite, // FULL WHITE for all text
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400, // BOLD when selected
                  ),
                ),
              ),
              if (isExpandable)
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: _kWhite, // FULL WHITE
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubDrawerItem(SubNavigationItem subItem) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _currentPageTitle = subItem.label; // CHANGED: update top bar title
        });
        _navigateToSubPage(subItem.route, subItem.label);
      },
      child: Container(
        margin: const EdgeInsets.only(left: 24, right: 12, top: 2, bottom: 2),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Show icon if available, otherwise show dot
              if (subItem.icon != null)
                Icon(
                  subItem.icon,
                  color: _kWhite, // FULL WHITE
                  size: 18,
                )
              else
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: _kWhite, // FULL WHITE
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  subItem.label,
                  style: const TextStyle(
                    color: _kWhite, // FULL WHITE
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
  final bool isExpandable;
  final List<SubNavigationItem>? subItems;

  NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
    this.isExpandable = false,
    this.subItems,
  });
}

class SubNavigationItem {
  final String label;
  final String route;
  final IconData? icon;

  SubNavigationItem({
    required this.label,
    required this.route,
    this.icon,
  });
}
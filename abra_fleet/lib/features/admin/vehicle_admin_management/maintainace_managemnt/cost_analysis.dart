import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Constants
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kInfoColor = Color(0xFF0288D1);

// 1. DATA MODELS FOR COST ANALYSIS
class CategoryCost {
  final String name;
  final double amount;
  final double percentage; // A value between 0.0 and 1.0

  CategoryCost({
    required this.name,
    required this.amount,
    required this.percentage,
  });
}

class VendorCost {
  final String name;
  final double totalCost;
  final int jobs;
  final double rating;
  
  // Calculated property for average cost
  double get avgCost => totalCost / jobs;

  VendorCost({
    required this.name,
    required this.totalCost,
    required this.jobs,
    required this.rating,
  });
}


// ============ COST ANALYSIS SCREEN ============
class CostAnalysisScreen extends StatefulWidget {
  final VoidCallback onBack;
  const CostAnalysisScreen({required this.onBack, Key? key}) : super(key: key);

  @override
  State<CostAnalysisScreen> createState() => _CostAnalysisScreenState();
}

class _CostAnalysisScreenState extends State<CostAnalysisScreen> {
  String _viewType = 'category'; // 'category' or 'vendor'

  // Mock Data using the new models
  final List<CategoryCost> _categoryCosts = [
    CategoryCost(name: 'Parts & Materials', amount: 18000, percentage: 0.40),
    CategoryCost(name: 'Labor', amount: 15000, percentage: 0.33),
    CategoryCost(name: 'Services', amount: 12000, percentage: 0.27),
  ];
  
  final List<VendorCost> _vendorCosts = [
    VendorCost(name: 'Premium Auto Service', totalCost: 18500, jobs: 12, rating: 4.8),
    VendorCost(name: 'Dubai Maintenance Hub', totalCost: 16200, jobs: 15, rating: 4.5),
    VendorCost(name: 'Gulf Auto Care', totalCost: 10300, jobs: 8, rating: 4.7),
  ];
  
  // Calculate total cost from category data
  double get _totalCost => _categoryCosts.fold(0, (sum, item) => sum + item.amount);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monthly Maintenance Cost',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Total Cost Card
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: kInfoColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kInfoColor.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Text(
                  '₹${NumberFormat('#,##0').format(_totalCost)}',
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryColor),
                ),
                const SizedBox(height: 8),
                const Text('Total Cost This Month',
                    style: TextStyle(color: kTextSecondaryColor)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // View Toggle Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => _viewType = 'category'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _viewType == 'category' ? kPrimaryColor : Colors.grey.shade300,
                    foregroundColor: _viewType == 'category' ? Colors.white : Colors.black,
                  ),
                  child: const Text('By Category'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => _viewType = 'vendor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _viewType == 'vendor' ? kPrimaryColor : Colors.grey.shade300,
                    foregroundColor: _viewType == 'vendor' ? Colors.white : Colors.black,
                  ),
                  child: const Text('By Vendor'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Display Based on View Type
          if (_viewType == 'category')
            _buildCategoryView()
          else
            _buildVendorView(),
        ],
      ),
    );
  }

  Widget _buildCategoryView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cost Breakdown by Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ..._categoryCosts.map((category) => 
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCostItem(category),
          ),
        ).toList(),
      ],
    );
  }

  Widget _buildVendorView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cost Breakdown by Vendor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ..._vendorCosts.map((vendor) => 
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildVendorCostCard(vendor),
          ),
        ).toList(),
      ],
    );
  }

  Widget _buildCostItem(CategoryCost category) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(category.name,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('₹${NumberFormat('#,##0').format(category.amount)}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: kPrimaryColor)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: category.percentage,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryColor),
          ),
        ),
      ],
    );
  }

  Widget _buildVendorCostCard(VendorCost vendor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(vendor.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(vendor.rating.toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric('Total Cost', '₹${NumberFormat('#,##0').format(vendor.totalCost)}'),
                _buildMetric('Jobs', vendor.jobs.toString()),
                _buildMetric('Avg Cost/Job', '₹${NumberFormat('#,##0').format(vendor.avgCost)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: kTextSecondaryColor)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: kPrimaryColor)),
      ],
    );
  }
}
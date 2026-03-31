// ============================================================================
// VEHICLE MASTER SCREEN - REDESIGNED - PART 1/5
// UI Similar to driver_list_page.dart with MORE cell spacing & padding
// Advanced Filters: 2 Rows (Country/State/City + Vehicle-specific)
// Export: Excel, PDF, WhatsApp
// Horizontal Scrolling: Cursor-based
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:abra_fleet/features/admin/vehicle_admin_management/vehicle_master/add_vehicle.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/vehicle_master/bulk_import_vehicles.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/maintainace_managemnt/maintainance_management.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/core/services/document_storage_service.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html show AnchorElement, Blob, Url;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ============================================================================
// COLOR SCHEME - Same as driver_list_page.dart
// ============================================================================
const Color primaryColor = Color(0xFF1B7FA8);
const Color darkPrimaryColor = Color(0xFF0D5A7A);
const Color accentColor = Color(0xFF2D3E50);
const Color lightBackgroundColor = Color(0xFFF5F9FA);
const Color cardBackgroundColor = Colors.white;
const Color borderColor = Color(0xFFE0E0E0);
const Color textPrimaryColor = Color(0xFF2D3E50);
const Color textSecondaryColor = Color(0xFF6B7280);

// ============================================================================
// VEHICLE DATA MODEL
// ============================================================================
class _VehicleData {
  final String id;
  final String vehicleId;
  final String registration;
  final String type;
  final String model;
  final String status;
  final String year;
  final String engineType;
  final String engineCapacity;
  final String seatingCapacity;
  final String mileage;
  final String lastServiceDate;
  final String nextServiceDue;
  final String? assignedDriverName;
  final String? assignedDriverId;
  final DateTime? onboardedDate;
  final List<Map<String, dynamic>> documents;
  final String? vendor;
  final int assignedCustomersCount;
  final int maintenanceScheduleCount;
  final String? country;
  final String? state;
  final String? city;

  const _VehicleData({
    required this.id,
    required this.vehicleId,
    required this.registration,
    required this.type,
    required this.model,
    required this.status,
    required this.year,
    required this.engineType,
    required this.engineCapacity,
    required this.seatingCapacity,
    required this.mileage,
    required this.lastServiceDate,
    required this.nextServiceDue,
    this.assignedDriverName,
    this.assignedDriverId,
    this.onboardedDate,
    this.documents = const [],
    this.vendor,
    this.assignedCustomersCount = 0,
    this.maintenanceScheduleCount = 0,
    this.country,
    this.state,
    this.city,
  });

  bool get hasExpiredDocuments {
    final now = DateTime.now();
    return documents.any((doc) {
      final expiryDate = doc['expiryDate'];
      return expiryDate != null && DateTime.parse(expiryDate).isBefore(now);
    });
  }

  bool get hasExpiringSoonDocuments {
    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));
    return documents.any((doc) {
      final expiryDate = doc['expiryDate'];
      if (expiryDate == null) return false;
      final expiry = DateTime.parse(expiryDate);
      return expiry.isAfter(now) && expiry.isBefore(thirtyDaysFromNow);
    });
  }

  factory _VehicleData.fromBackend(Map<String, dynamic> data) {
    String mongoId = '';
    if (data['_id'] != null) {
      if (data['_id'] is Map) {
        mongoId = data['_id']['\$oid'] ?? '';
      } else {
        mongoId = data['_id'].toString();
      }
    }

    String? driverName;
    String? driverId;
    
    if (data['assignedDriver'] != null) {
      final driver = data['assignedDriver'];
      driverName = driver['name'] ?? driver['personalInfo']?['firstName'] ?? 'Unknown Driver';
      driverId = driver['driverId'];
    }

    List<Map<String, dynamic>> vehicleDocs = [];
    if (data['documents'] != null && data['documents'] is List) {
      vehicleDocs = (data['documents'] as List).map((doc) => Map<String, dynamic>.from(doc)).toList();
    }

    DateTime? onboarded;
    if (data['onboardedDate'] != null) {
      try {
        onboarded = DateTime.parse(data['onboardedDate']);
      } catch (e) {
        onboarded = null;
      }
    }

    int assignedCount = 0;
    if (data['assignedCustomers'] != null && data['assignedCustomers'] is List) {
      assignedCount = (data['assignedCustomers'] as List).length;
    }

    int maintenanceCount = 0;
    if (data['maintenanceScheduleCount'] != null) {
      maintenanceCount = int.tryParse(data['maintenanceScheduleCount'].toString()) ?? 0;
    }

    return _VehicleData(
      id: mongoId,
      vehicleId: data['vehicleId'] ?? '',
      registration: data['registrationNumber'] ?? '',
      type: (data['type'] ?? '').toString().toUpperCase(),
      model: '${data['make'] ?? ''} ${data['model'] ?? ''}'.trim(),
      status: (data['status'] ?? 'active').toString().toUpperCase(),
      year: (data['year'] ?? data['yearOfManufacture'] ?? '').toString(),
      engineType: data['specifications']?['engineType'] ?? data['engineType'] ?? '',
      engineCapacity: (data['specifications']?['engineCapacity'] ?? data['engineCapacity'] ?? '').toString(),
      seatingCapacity: (() {
        try {
          if (data['seatCapacity'] != null) {
            return data['seatCapacity'].toString();
          }
          
          if (data['seatingCapacity'] != null) {
            return data['seatingCapacity'].toString();
          }
          
          if (data['capacity'] != null) {
            final capacity = data['capacity'];
            if (capacity is Map && capacity['passengers'] != null) {
              return capacity['passengers'].toString();
            } else if (capacity is num) {
              return capacity.toString();
            } else {
              return capacity.toString();
            }
          }
          
          return '4';
        } catch (e) {
          print('Error parsing seating capacity: $e');
          return '4';
        }
      })(),
      mileage: (data['specifications']?['mileage'] ?? data['mileage'] ?? '').toString(),
      lastServiceDate: data['maintenance']?['lastServiceDate'] != null 
          ? DateTime.parse(data['maintenance']['lastServiceDate']).toString().split(' ')[0]
          : '-',
      nextServiceDue: data['maintenance']?['nextServiceDue'] != null
          ? DateTime.parse(data['maintenance']['nextServiceDue']).toString().split(' ')[0]
          : '-',
      assignedDriverName: driverName,
      assignedDriverId: driverId,
      onboardedDate: onboarded,
      documents: vehicleDocs,
      vendor: data['vendor'],
      assignedCustomersCount: assignedCount,
      maintenanceScheduleCount: maintenanceCount,
      country: data['country'],
      state: data['state'],
      city: data['city'],
    );
  }

  Map<String, dynamic> toMap() {
    final seatCapacity = int.tryParse(seatingCapacity) ?? 4;
    final driverSeats = assignedDriverName != null ? 1 : 0;
    final availableSeats = seatCapacity - driverSeats - assignedCustomersCount;
    
    return {
      'Vehicle ID': vehicleId,
      'Registration Number': registration,
      'Vehicle Type': type,
      'Make & Model': model,
      'Year of Manufacture': year,
      'Engine Type': engineType,
      'Engine Capacity (CC)': engineCapacity,
      'Seating Capacity': seatingCapacity,
      'Seat Availability': '$availableSeats/$seatCapacity',
      'Mileage (km/l)': mileage,
      'Status': status,
      'Vendor': vendor ?? 'Own Fleet',
      'Assigned Driver': assignedDriverName ?? 'Not Assigned',
      'Assigned Customers': assignedCustomersCount.toString(),
      'Last Service Date': lastServiceDate,
      'Next Service Due': nextServiceDue,
      'Onboarded Date': onboardedDate != null ? onboardedDate.toString().split(' ')[0] : 'Not Onboarded',
      'Document Status': hasExpiredDocuments 
          ? 'Has Expired Documents' 
          : hasExpiringSoonDocuments 
              ? 'Expiring Soon' 
              : documents.isNotEmpty 
                  ? 'All Valid' 
                  : 'No Documents',
      'Country': country ?? 'Not Set',
      'State': state ?? 'Not Set',
      'City': city ?? 'Not Set',
    };
  }
}

// ============================================================================
// END OF PART 1
// Continue with Part 2
// ============================================================================

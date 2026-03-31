import 'package:mongo_dart/mongo_dart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class MongoDBService {
  static final MongoDBService _instance = MongoDBService._internal();
  Db? _db;
  
  String get _connectionString => 
      dotenv.env['MONGODB_URI'] ?? 'mongodb://localhost:27017/abra_fleet';
  static const String _usersCollection = 'users';
  static const String _driversCollection = 'drivers';
  static const String _vehiclesCollection = 'vehicles';

  factory MongoDBService() {
    return _instance;
  }

  MongoDBService._internal();

  Future<Db> get database async {
    if (_db == null || !_db!.isConnected) {
      _db = await _connect();
    }
    return _db!;
  }

  Future<Db> _connect() async {
    try {
      debugPrint('🔄 Connecting to MongoDB: ${_connectionString.replaceAll(RegExp(r'://[^:]+:[^@]+@'), '://***:***@')}');
      final db = await Db.create(_connectionString);
      await db.open();
      debugPrint('✅ Connected to MongoDB');
      return db;
    } catch (e) {
      debugPrint('❌ Error connecting to MongoDB: $e');
      rethrow;
    }
  }

  // User Operations
  Future<void> insertUser(Map<String, dynamic> user) async {
    final db = await database;
    await db.collection(_usersCollection).insert(user);
  }

  Future<Map<String, dynamic>?> findUser(String email) async {
    final db = await database;
    return await db.collection(_usersCollection).findOne(where.eq('email', email));
  }

  // Driver Operations
  Future<void> insertDriver(Map<String, dynamic> driver) async {
    final db = await database;
    await db.collection(_driversCollection).insert(driver);
  }

  Future<List<Map<String, dynamic>>> getAllDrivers() async {
    final db = await database;
    return await db.collection(_driversCollection).find().toList();
  }

  // Vehicle Operations
  Future<void> insertVehicle(Map<String, dynamic> vehicle) async {
    final db = await database;
    await db.collection(_vehiclesCollection).insert(vehicle);
  }

  Future<List<Map<String, dynamic>>> getAllVehicles() async {
    final db = await database;
    return await db.collection(_vehiclesCollection).find().toList();
  }

  // Close the database connection
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}

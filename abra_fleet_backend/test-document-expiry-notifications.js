// Test script to check document expiry notifications
// This script checks for documents expiring today and verifies notification system

const { MongoClient } = require('mongodb');
const admin = require('firebase-admin');

// MongoDB connection
require('dotenv').config();
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

// Initialize Firebase Admin (if not already initialized)
if (!admin.apps.length) {
  try {
    admin.initializeApp({
      credential: admin.credential.cert(require('./serviceAccountKey.json')),
      databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
    });
    console.log('✅ Firebase Admin initialized');
  } catch (error) {
    console.log('⚠️ Firebase already initialized or error:', error.message);
  }
}

async function testDocumentExpiryNotifications() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    const driversCollection = db.collection('drivers');
    const vehiclesCollection = db.collection('vehicles');
    const notificationsCollection = db.collection('notifications');
    
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    const thirtyDaysFromNow = new Date(today);
    thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30);
    
    console.log('📅 Date Ranges:');
    console.log(`   Today: ${today.toISOString().split('T')[0]}`);
    console.log(`   Tomorrow: ${tomorrow.toISOString().split('T')[0]}`);
    console.log(`   30 Days from now: ${thirtyDaysFromNow.toISOString().split('T')[0]}\n`);
    
    // ========== CHECK DRIVER DOCUMENTS ==========
    console.log('🔍 ========== CHECKING DRIVER DOCUMENTS ==========\n');
    
    const driversWithDocs = await driversCollection.find({
      'documents': { $exists: true, $ne: [] }
    }).toArray();
    
    console.log(`📊 Found ${driversWithDocs.length} drivers with documents\n`);
    
    let expiredDriverDocs = 0;
    let expiringTodayDriverDocs = 0;
    let expiringSoonDriverDocs = 0;
    
    for (const driver of driversWithDocs) {
      if (!driver.documents || !Array.isArray(driver.documents) || driver.documents.length === 0) continue;
      
      for (const doc of driver.documents) {
        if (!doc || !doc.expiryDate) continue;
        
        const expiryDate = new Date(doc.expiryDate);
        expiryDate.setHours(0, 0, 0, 0);
        
        if (expiryDate < today) {
          expiredDriverDocs++;
          console.log(`❌ EXPIRED - Driver: ${driver.name}`);
          console.log(`   Document: ${doc.documentType} - ${doc.documentName}`);
          console.log(`   Expired on: ${expiryDate.toISOString().split('T')[0]}`);
          console.log(`   Driver ID: ${driver.driverId}\n`);
        } else if (expiryDate.getTime() === today.getTime()) {
          expiringTodayDriverDocs++;
          console.log(`⚠️ EXPIRING TODAY - Driver: ${driver.name}`);
          console.log(`   Document: ${doc.documentType} - ${doc.documentName}`);
          console.log(`   Expires: ${expiryDate.toISOString().split('T')[0]}`);
          console.log(`   Driver ID: ${driver.driverId}\n`);
        } else if (expiryDate <= thirtyDaysFromNow) {
          expiringSoonDriverDocs++;
          const daysUntilExpiry = Math.ceil((expiryDate - today) / (1000 * 60 * 60 * 24));
          console.log(`⏰ EXPIRING SOON - Driver: ${driver.name}`);
          console.log(`   Document: ${doc.documentType} - ${doc.documentName}`);
          console.log(`   Expires in: ${daysUntilExpiry} days (${expiryDate.toISOString().split('T')[0]})`);
          console.log(`   Driver ID: ${driver.driverId}\n`);
        }
      }
    }
    
    // ========== CHECK VEHICLE DOCUMENTS ==========
    console.log('🔍 ========== CHECKING VEHICLE DOCUMENTS ==========\n');
    
    const vehiclesWithDocs = await vehiclesCollection.find({
      'documents': { $exists: true, $ne: [] }
    }).toArray();
    
    console.log(`📊 Found ${vehiclesWithDocs.length} vehicles with documents\n`);
    
    let expiredVehicleDocs = 0;
    let expiringTodayVehicleDocs = 0;
    let expiringSoonVehicleDocs = 0;
    
    for (const vehicle of vehiclesWithDocs) {
      if (!vehicle.documents || !Array.isArray(vehicle.documents) || vehicle.documents.length === 0) continue;
      
      for (const doc of vehicle.documents) {
        if (!doc || !doc.expiryDate) continue;
        
        const expiryDate = new Date(doc.expiryDate);
        expiryDate.setHours(0, 0, 0, 0);
        
        if (expiryDate < today) {
          expiredVehicleDocs++;
          console.log(`❌ EXPIRED - Vehicle: ${vehicle.registrationNumber}`);
          console.log(`   Document: ${doc.documentType} - ${doc.documentName}`);
          console.log(`   Expired on: ${expiryDate.toISOString().split('T')[0]}`);
          console.log(`   Vehicle ID: ${vehicle.vehicleId}\n`);
        } else if (expiryDate.getTime() === today.getTime()) {
          expiringTodayVehicleDocs++;
          console.log(`⚠️ EXPIRING TODAY - Vehicle: ${vehicle.registrationNumber}`);
          console.log(`   Document: ${doc.documentType} - ${doc.documentName}`);
          console.log(`   Expires: ${expiryDate.toISOString().split('T')[0]}`);
          console.log(`   Vehicle ID: ${vehicle.vehicleId}\n`);
        } else if (expiryDate <= thirtyDaysFromNow) {
          expiringSoonVehicleDocs++;
          const daysUntilExpiry = Math.ceil((expiryDate - today) / (1000 * 60 * 60 * 24));
          console.log(`⏰ EXPIRING SOON - Vehicle: ${vehicle.registrationNumber}`);
          console.log(`   Document: ${doc.documentType} - ${doc.documentName}`);
          console.log(`   Expires in: ${daysUntilExpiry} days (${expiryDate.toISOString().split('T')[0]})`);
          console.log(`   Vehicle ID: ${vehicle.vehicleId}\n`);
        }
      }
    }
    
    // ========== SUMMARY ==========
    console.log('📊 ========== SUMMARY ==========\n');
    console.log('Driver Documents:');
    console.log(`   ❌ Expired: ${expiredDriverDocs}`);
    console.log(`   ⚠️ Expiring Today: ${expiringTodayDriverDocs}`);
    console.log(`   ⏰ Expiring Soon (30 days): ${expiringSoonDriverDocs}\n`);
    
    console.log('Vehicle Documents:');
    console.log(`   ❌ Expired: ${expiredVehicleDocs}`);
    console.log(`   ⚠️ Expiring Today: ${expiringTodayVehicleDocs}`);
    console.log(`   ⏰ Expiring Soon (30 days): ${expiringSoonVehicleDocs}\n`);
    
    const totalExpired = expiredDriverDocs + expiredVehicleDocs;
    const totalExpiringToday = expiringTodayDriverDocs + expiringTodayVehicleDocs;
    const totalExpiringSoon = expiringSoonDriverDocs + expiringSoonVehicleDocs;
    
    console.log('Total:');
    console.log(`   ❌ Expired: ${totalExpired}`);
    console.log(`   ⚠️ Expiring Today: ${totalExpiringToday}`);
    console.log(`   ⏰ Expiring Soon: ${totalExpiringSoon}\n`);
    
    // ========== CHECK NOTIFICATIONS ==========
    console.log('🔔 ========== CHECKING NOTIFICATIONS ==========\n');
    
    // Check for document expiry notifications
    const documentNotifications = await notificationsCollection.find({
      type: { $in: ['document_expired', 'document_expiring_soon'] }
    }).sort({ createdAt: -1 }).limit(10).toArray();
    
    console.log(`📬 Found ${documentNotifications.length} document expiry notifications (last 10)\n`);
    
    if (documentNotifications.length > 0) {
      for (const notif of documentNotifications) {
        console.log(`📧 Notification:`);
        console.log(`   Type: ${notif.type}`);
        console.log(`   Title: ${notif.title}`);
        console.log(`   Message: ${notif.message}`);
        console.log(`   Created: ${notif.createdAt}`);
        console.log(`   Read: ${notif.read ? 'Yes' : 'No'}\n`);
      }
    } else {
      console.log('⚠️ No document expiry notifications found in database\n');
    }
    
    // ========== RECOMMENDATIONS ==========
    console.log('💡 ========== RECOMMENDATIONS ==========\n');
    
    if (totalExpiringToday > 0) {
      console.log(`⚠️ URGENT: ${totalExpiringToday} document(s) expiring TODAY!`);
      console.log('   → Admin should receive immediate notification\n');
    }
    
    if (totalExpired > 0) {
      console.log(`❌ CRITICAL: ${totalExpired} document(s) already expired!`);
      console.log('   → Admin should have received notifications\n');
    }
    
    if (totalExpiringSoon > 0) {
      console.log(`⏰ INFO: ${totalExpiringSoon} document(s) expiring within 30 days`);
      console.log('   → Admin should receive advance warning notifications\n');
    }
    
    if (totalExpired === 0 && totalExpiringToday === 0 && totalExpiringSoon === 0) {
      console.log('✅ All documents are valid! No notifications needed.\n');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Test completed');
    process.exit(0);
  }
}

// Run the test
testDocumentExpiryNotifications();

#!/usr/bin/env node

const admin = require('./config/firebase');
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function createFirebaseAdminUser() {
  try {
    console.log('🔥 Creating Firebase Admin User...');
    
    // 1. Create Firebase Auth user
    const userRecord = await admin.auth().createUser({
      email: 'admin@abrafleet.com',
      password: 'admin123',
      displayName: 'Super Admin',
      emailVerified: true
    });
    
    console.log('✅ Firebase user created:', userRecord.uid);
    
    // 2. Update MongoDB with Firebase UID
    const client = new MongoClient(process.env.MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    
    // Update admin_users collection
    await db.collection('admin_users').updateOne(
      { email: 'admin@abrafleet.com' },
      { $set: { firebaseUid: userRecord.uid } }
    );
    
    // Update users collection
    await db.collection('users').updateOne(
      { email: 'admin@abrafleet.com' },
      { $set: { firebaseUid: userRecord.uid } }
    );
    
    console.log('✅ MongoDB updated with Firebase UID');
    
    await client.close();
    
    console.log('\n🎉 ADMIN USER READY!');
    console.log('Email: admin@abrafleet.com');
    console.log('Password: admin123');
    
  } catch (error) {
    if (error.code === 'auth/email-already-exists') {
      console.log('✅ Firebase user already exists');
      
      // Get existing user and update MongoDB
      const userRecord = await admin.auth().getUserByEmail('admin@abrafleet.com');
      
      const client = new MongoClient(process.env.MONGODB_URI);
      await client.connect();
      const db = client.db('abra_fleet');
      
      await db.collection('admin_users').updateOne(
        { email: 'admin@abrafleet.com' },
        { $set: { firebaseUid: userRecord.uid } }
      );
      
      await db.collection('users').updateOne(
        { email: 'admin@abrafleet.com' },
        { $set: { firebaseUid: userRecord.uid } }
      );
      
      console.log('✅ MongoDB updated with existing Firebase UID');
      await client.close();
      
      console.log('\n🎉 ADMIN USER READY!');
      console.log('Email: admin@abrafleet.com');
      console.log('Password: admin123');
    } else {
      console.error('❌ Error:', error.message);
    }
  }
}

createFirebaseAdminUser();
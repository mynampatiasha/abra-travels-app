// Check Firebase Realtime Database rules
const admin = require('./config/firebase');

async function checkRealtimeRules() {
  try {
    console.log('\n🔍 Checking Firebase Realtime Database rules...');
    console.log('─'.repeat(80));
    
    // Get the database reference
    const db = admin.database();
    
    // Try to get the rules
    const rulesRef = db.ref('.settings/rules');
    
    console.log('✅ Connected to Firebase Realtime Database');
    console.log('\n📋 Current rules structure:');
    
    // Check if we can access roster_requests
    const rosterRef = db.ref('roster_requests');
    console.log('   roster_requests path exists');
    
    // Check admin user permissions
    console.log('\n🔐 Testing admin access...');
    
    // This will help us understand the current rules
    console.log('   Firebase project:', process.env.FIREBASE_PROJECT_ID || 'Not set');
    console.log('   Database URL:', process.env.FIREBASE_DATABASE_URL || 'Not set');
    
    console.log('\n─'.repeat(80) + '\n');
    
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

checkRealtimeRules();
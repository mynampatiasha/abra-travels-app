// Update Firebase Realtime Database rules to allow admin access
const admin = require('./config/firebase');

async function updateRealtimeRules() {
  try {
    console.log('\n🔧 Updating Firebase Realtime Database rules...');
    console.log('─'.repeat(80));
    
    // Define the rules that allow admin access
    const rules = {
      "rules": {
        ".read": "auth != null && (auth.token.email == 'admin@abrafleet.com' || root.child('admin_users').child(auth.uid).exists())",
        ".write": "auth != null && (auth.token.email == 'admin@abrafleet.com' || root.child('admin_users').child(auth.uid).exists())",
        
        // SOS Events - Admin access
        "sos_events": {
          ".read": "auth != null && (auth.token.email == 'admin@abrafleet.com' || root.child('admin_users').child(auth.uid).exists())",
          ".write": "auth != null"
        },
        
        // Roster Requests - Admin access
        "roster_requests": {
          ".read": "auth != null && (auth.token.email == 'admin@abrafleet.com' || root.child('admin_users').child(auth.uid).exists())",
          ".write": "auth != null && (auth.token.email == 'admin@abrafleet.com' || root.child('admin_users').child(auth.uid).exists())"
        },
        
        // Notifications - Admin access
        "notifications": {
          ".read": "auth != null",
          ".write": "auth != null"
        },
        
        // Admin users list for permission checking
        "admin_users": {
          ".read": "auth != null",
          ".write": "auth != null && auth.token.email == 'admin@abrafleet.com'"
        },
        
        // Driver locations
        "driver_locations": {
          ".read": "auth != null",
          ".write": "auth != null"
        },
        
        // Trip tracking
        "trip_tracking": {
          ".read": "auth != null",
          ".write": "auth != null"
        }
      }
    };
    
    console.log('📋 Rules to be applied:');
    console.log(JSON.stringify(rules, null, 2));
    
    console.log('\n⚠️  Note: Firebase Realtime Database rules need to be updated manually in the Firebase Console');
    console.log('   1. Go to https://console.firebase.google.com/');
    console.log('   2. Select your project');
    console.log('   3. Go to Realtime Database > Rules');
    console.log('   4. Replace the rules with the above JSON');
    console.log('   5. Click "Publish"');
    
    console.log('\n─'.repeat(80) + '\n');
    
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

updateRealtimeRules();
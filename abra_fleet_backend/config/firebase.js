// config/firebase.js - FIREBASE REMOVED - JWT ONLY
// ============================================================================
// THIS FILE IS KEPT FOR BACKWARD COMPATIBILITY BUT FIREBASE IS DISABLED
// ALL AUTHENTICATION NOW USES JWT TOKENS ONLY
// ============================================================================

console.warn('⚠️  WARNING: Firebase config accessed but Firebase has been removed!');
console.warn('   All authentication now uses JWT tokens.');
console.warn('   Please update your code to use JWT authentication.');

// Throw error if any Firebase functionality is accessed
const firebaseStub = new Proxy({}, {
  get(target, prop) {
    throw new Error(`Firebase has been removed from this application. Property '${prop}' is no longer available. Please use JWT authentication instead.`);
  }
});

module.exports = firebaseStub;
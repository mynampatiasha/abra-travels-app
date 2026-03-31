// Test syntax of admin-clients-unified.js
try {
  const route = require('./routes/admin-clients-unified');
  console.log('✅ File loaded successfully');
  console.log('Type:', typeof route);
} catch (error) {
  console.log('❌ Syntax error:', error.message);
  console.log('Stack:', error.stack);
}
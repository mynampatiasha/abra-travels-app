// Debug script to check which route is undefined
const express = require('express');

console.log('Checking route imports...');

try {
  const { verifyToken, requireRole } = require('./middleware/auth');
  console.log('✅ verifyToken:', typeof verifyToken);
  console.log('✅ requireRole:', typeof requireRole);
} catch (error) {
  console.log('❌ Auth middleware error:', error.message);
}

try {
  const { checkUserPermission, checkEitherPermission } = require('./middleware/user_permissions');
  console.log('✅ checkUserPermission:', typeof checkUserPermission);
  console.log('✅ checkEitherPermission:', typeof checkEitherPermission);
} catch (error) {
  console.log('❌ User permissions middleware error:', error.message);
}

try {
  const adminCustomerRoutes = require('./routes/admin-customers');
  console.log('✅ adminCustomerRoutes:', typeof adminCustomerRoutes);
} catch (error) {
  console.log('❌ adminCustomerRoutes error:', error.message);
}

try {
  const adminClientsUnifiedRoutes = require('./routes/admin-clients-unified-test');
  console.log('✅ adminClientsUnifiedRoutes:', typeof adminClientsUnifiedRoutes);
} catch (error) {
  console.log('❌ adminClientsUnifiedRoutes error:', error.message);
}

try {
  const adminCustomersUnifiedRoutes = require('./routes/admin-customers-unified');
  console.log('✅ adminCustomersUnifiedRoutes:', typeof adminCustomersUnifiedRoutes);
} catch (error) {
  console.log('❌ adminCustomersUnifiedRoutes error:', error.message);
}

try {
  const employeeManagementRoutes = require('./routes/employeeManagement');
  console.log('✅ employeeManagementRoutes:', typeof employeeManagementRoutes);
} catch (error) {
  console.log('❌ employeeManagementRoutes error:', error.message);
}

console.log('Route debugging complete.');
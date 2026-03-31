// backend/routes/employee_permissions.js
// ============================================================================
// 🔐 EMPLOYEE PERMISSIONS ENDPOINT
// ============================================================================
// Returns permissions for employees from employee_admins collection
// ============================================================================

const express = require('express');
const router = express.Router();
const { verifyJWT } = require('./jwt_router');

// ============================================================================
// 📥 GET USER PERMISSIONS BY EMAIL
// ============================================================================
router.get('/api/employee-management/permissions/:email', verifyJWT, async (req, res) => {
  try {
    console.log('\n🔐 FETCHING EMPLOYEE PERMISSIONS');
    console.log('─'.repeat(80));
    
    const { email } = req.params;
    const db = req.db;
    
    if (!db) {
      console.error('❌ Database not available');
      return res.status(503).json({ 
        success: false, 
        message: 'Database not available' 
      });
    }
    
    console.log('📧 Email:', email);
    
    // First, check if user is in employee_admins collection
    const employee = await db.collection('employee_admins').findOne({ 
      email: email.toLowerCase() 
    });
    
    if (employee) {
      console.log('✅ Found in employee_admins collection');
      console.log('👤 Name:', employee.name_parson);
      console.log('🎭 Role:', employee.role);
      console.log('🔐 Permissions:', Object.keys(employee.permissions || {}).length, 'items');
      
      // Return employee permissions
      return res.json({ 
        success: true, 
        data: {
          permissions: employee.permissions || {},
          role: employee.role,
          name: employee.name_parson,
          source: 'employee_admins',
        }
      });
    }
    
    // If not found in employee_admins, check users collection
    const user = await db.collection('users').findOne({ 
      email: email.toLowerCase() 
    });
    
    if (user) {
      console.log('✅ Found in users collection');
      console.log('👤 Name:', user.name);
      console.log('🎭 Role:', user.role);
      
      // If user is admin, return full permissions
      if (user.role === 'super_admin' || user.role === 'admin') {
        console.log('🔓 Admin user - full access granted');
        return res.json({ 
          success: true, 
          data: {
            permissions: {}, // Empty = full access
            role: user.role,
            name: user.name,
            source: 'users',
            isAdmin: true,
          }
        });
      }
      
      // Regular user from users collection (customer, driver, etc.)
      return res.json({ 
        success: true, 
        data: {
          permissions: user.permissions || {},
          role: user.role,
          name: user.name,
          source: 'users',
        }
      });
    }
    
    console.log('❌ User not found in any collection');
    return res.status(404).json({ 
      success: false, 
      message: 'User not found' 
    });
    
  } catch (error) {
    console.error('❌ Error fetching permissions:', error);
    console.error('Stack:', error.stack);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// ============================================================================
// 🔄 REFRESH USER PERMISSIONS
// ============================================================================
router.post('/api/employee-management/permissions/refresh', verifyJWT, async (req, res) => {
  try {
    const userEmail = req.user.email;
    const db = req.db;
    
    console.log('🔄 Refreshing permissions for:', userEmail);
    
    // Get fresh permissions
    const employee = await db.collection('employee_admins').findOne({ 
      email: userEmail.toLowerCase() 
    });
    
    if (employee) {
      return res.json({ 
        success: true, 
        data: {
          permissions: employee.permissions || {},
          role: employee.role,
          name: employee.name_parson,
        }
      });
    }
    
    const user = await db.collection('users').findOne({ 
      email: userEmail.toLowerCase() 
    });
    
    if (user) {
      return res.json({ 
        success: true, 
        data: {
          permissions: user.permissions || {},
          role: user.role,
          name: user.name,
          isAdmin: user.role === 'super_admin' || user.role === 'admin',
        }
      });
    }
    
    return res.status(404).json({ 
      success: false, 
      message: 'User not found' 
    });
    
  } catch (error) {
    console.error('❌ Error refreshing permissions:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

module.exports = router;
// routes/role_router.js - Role management routes for Abra Travel
const express = require('express');
const router = express.Router();
const roleController = require('../controllers/roleController');
const { verifyToken } = require('../middleware/auth');

// All routes require authentication
router.use(verifyToken);

// Get all roles
router.get('/', roleController.getAllRoles);

// Update role permissions
router.put('/:roleId/permissions', roleController.updateRolePermissions);

// Initialize default roles (run once)
router.post('/initialize', roleController.initializeRoles);

module.exports = router;

// routes/userRole_router.js - User management routes for Abra Travel
const express = require('express');
const router = express.Router();
const userRoleController = require('../controllers/userRoleController');
const { verifyToken } = require('../middleware/auth');

// All routes require authentication
router.use(verifyToken);

// Get all users
router.get('/', userRoleController.getAllUsers);

// Search users
router.get('/search', userRoleController.searchUsers);

// Get user by ID
router.get('/:id', userRoleController.getUserById);

// Create new user
router.post('/', userRoleController.createUser);

// Update user
router.put('/:id', userRoleController.updateUser);

// Delete user
router.delete('/:id', userRoleController.deleteUser);

// Toggle user status
router.patch('/:id/toggle-status', userRoleController.toggleUserStatus);

module.exports = router;

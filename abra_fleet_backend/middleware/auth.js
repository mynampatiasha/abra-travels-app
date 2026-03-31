// middleware/auth.js - JWT-ONLY AUTH MIDDLEWARE
// ============================================================================
// USES JWT AUTHENTICATION ONLY - NO FIREBASE
// ============================================================================

// Import JWT middleware from jwt_router
const { verifyJWT, requireRole } = require('../routes/jwt_router');

/**
 * JWT Authentication Middleware - Uses JWT tokens only
 * This middleware is now just a wrapper around the JWT middleware
 */
const verifyToken = verifyJWT;

module.exports = {
  verifyJWT,
  verifyToken,
  requireRole
};
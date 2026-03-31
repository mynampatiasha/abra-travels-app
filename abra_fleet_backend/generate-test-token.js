const jwt = require('jsonwebtoken');
require('dotenv').config();

// Use the same secret as in your .env file
const secret = process.env.JWT_SECRET || 'your_jwt_secret_key_here';

// Create a test user payload
const payload = {
  id: 'test-user-123',
  email: 'test@example.com',
  role: 'admin'
};

// Generate token
const token = jwt.sign(payload, secret, { expiresIn: '1d' });

console.log('Test JWT Token:');
console.log(token);

console.log('\nUse this token in your WebSocket connection header like this:');
console.log(`Authorization: Bearer ${token}`);

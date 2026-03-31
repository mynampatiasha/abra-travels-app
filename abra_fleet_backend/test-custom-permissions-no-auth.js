// test-custom-permissions-no-auth.js - Direct MongoDB test without API authentication
// Run with: node test-custom-permissions-no-auth.js

require('dotenv').config();
const mongoose = require('mongoose');

// Import models
const UserRole = require('./models/UserRole');
const Role = require('./models/Role');

const M
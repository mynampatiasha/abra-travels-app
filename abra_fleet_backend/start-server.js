#!/usr/bin/env node

/**
 * Abra Fleet Backend Startup Script
 * Validates environment and starts the server safely
 */

const fs = require('fs');
const path = require('path');

console.log('🚀 Starting Abra Fleet Backend...\n');

// Check if .env file exists
const envPath = path.join(__dirname, '.env');
if (!fs.existsSync(envPath)) {
  console.error('❌ CRITICAL ERROR: .env file not found!');
  console.error('   Expected location:', envPath);
  console.error('   Please create the .env file with required configuration.');
  process.exit(1);
}

// Load environment variables
require('dotenv').config({ path: envPath });

// Validate critical environment variables
const requiredVars = {
  'MONGODB_URI': 'MongoDB connection string',
  'JWT_SECRET': 'JWT signing secret for authentication'
};

const optionalVars = {
  'PORT': 'Server port (defaults to 3000)',
  'NODE_ENV': 'Environment mode (defaults to development)',
  'SMTP_HOST': 'Email server host',
  'SMTP_USER': 'Email username',
  'SMTP_PASSWORD': 'Email password'
};

console.log('🔍 Validating environment configuration...\n');

// Check required variables
let hasErrors = false;
for (const [varName, description] of Object.entries(requiredVars)) {
  const value = process.env[varName];
  if (!value || value.trim() === '') {
    console.error(`❌ MISSING REQUIRED: ${varName}`);
    console.error(`   Description: ${description}`);
    hasErrors = true;
  } else {
    console.log(`✅ ${varName}: SET`);
  }
}

// Check optional variables
console.log('\n📋 Optional configuration:');
for (const [varName, description] of Object.entries(optionalVars)) {
  const value = process.env[varName];
  if (value && value.trim() !== '') {
    console.log(`✅ ${varName}: SET`);
  } else {
    console.log(`⚠️  ${varName}: NOT SET (${description})`);
  }
}

if (hasErrors) {
  console.error('\n❌ STARTUP FAILED: Missing required environment variables');
  console.error('Please check your .env file and ensure all required variables are set.');
  process.exit(1);
}

console.log('\n✅ All validations passed! Starting server...\n');

// Start the main server
try {
  require('./index.js');
} catch (error) {
  console.error('\n❌ STARTUP ERROR:', error.message);
  console.error('Stack trace:', error.stack);
  process.exit(1);
}
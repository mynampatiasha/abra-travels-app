#!/usr/bin/env node

/**
 * Manual Diagnostic Checklist
 * Run this to identify Firebase remnants in your code
 */

const fs = require('fs');
const path = require('path');

console.log('🔍 FIREBASE REMOVAL DIAGNOSTIC CHECKLIST\n');
console.log('═'.repeat(70));

// Check 1: Environment Variables
console.log('\n✅ CHECK 1: Environment Variables');
console.log('─'.repeat(70));

const envPath = path.join(process.cwd(), '.env');
if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, 'utf8');
  
  const hasJwtSecret = envContent.includes('JWT_SECRET');
  const hasFirebase = envContent.includes('FIREBASE') || envContent.includes('firebase');
  
  console.log(`JWT_SECRET present: ${hasJwtSecret ? '✅ YES' : '❌ NO - ADD THIS!'}`);
  console.log(`Firebase config present: ${hasFirebase ? '⚠️  YES - Consider removing' : '✅ NO'}`);
  
  if (!hasJwtSecret) {
    console.log('\n⚠️  ACTION REQUIRED:');
    console.log('   Add to .env file:');
    console.log('   JWT_SECRET=your-super-secret-key-here');
  }
} else {
  console.log('❌ .env file not found');
}

// Check 2: package.json dependencies
console.log('\n✅ CHECK 2: Package Dependencies');
console.log('─'.repeat(70));

const packagePath = path.join(process.cwd(), 'package.json');
if (fs.existsSync(packagePath)) {
  const packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
  const deps = { ...packageJson.dependencies, ...packageJson.devDependencies };
  
  const hasFirebaseAdmin = deps['firebase-admin'];
  const hasJwt = deps['jsonwebtoken'];
  const hasBcrypt = deps['bcryptjs'] || deps['bcrypt'];
  
  console.log(`firebase-admin: ${hasFirebaseAdmin ? '⚠️  FOUND - Should remove' : '✅ Not found'}`);
  console.log(`jsonwebtoken: ${hasJwt ? '✅ FOUND' : '❌ MISSING - Run: npm install jsonwebtoken'}`);
  console.log(`bcryptjs: ${hasBcrypt ? '✅ FOUND' : '❌ MISSING - Run: npm install bcryptjs'}`);
  
  if (hasFirebaseAdmin) {
    console.log('\n⚠️  ACTION RECOMMENDED:');
    console.log('   Remove Firebase: npm uninstall firebase-admin');
  }
  
  if (!hasJwt || !hasBcrypt) {
    console.log('\n⚠️  ACTION REQUIRED:');
    console.log('   Install required packages:');
    if (!hasJwt) console.log('   npm install jsonwebtoken');
    if (!hasBcrypt) console.log('   npm install bcryptjs');
  }
}

// Check 3: Server.js configuration
console.log('\n✅ CHECK 3: Server Configuration');
console.log('─'.repeat(70));

const serverPath = path.join(process.cwd(), 'server.js');
if (fs.existsSync(serverPath)) {
  const serverContent = fs.readFileSync(serverPath, 'utf8');
  
  const hasFirebaseImport = serverContent.includes("require('firebase-admin')");
  const hasJwtImport = serverContent.includes('jwt_router') || serverContent.includes('verifyJWT');
  const hasJwtMiddleware = serverContent.includes('verifyJWT,') || serverContent.includes('verifyJWT)');
  
  console.log(`Firebase import: ${hasFirebaseImport ? '⚠️  FOUND - Remove it' : '✅ Not found'}`);
  console.log(`JWT router import: ${hasJwtImport ? '✅ FOUND' : '❌ MISSING'}`);
  console.log(`JWT middleware used: ${hasJwtMiddleware ? '✅ FOUND' : '❌ MISSING'}`);
}

// Check 4: JWT Router exists
console.log('\n✅ CHECK 4: JWT Authentication Router');
console.log('─'.repeat(70));

const jwtRouterPath = path.join(process.cwd(), 'routes', 'jwt_router.js');
if (fs.existsSync(jwtRouterPath)) {
  console.log('✅ jwt_router.js exists');
  
  const jwtContent = fs.readFileSync(jwtRouterPath, 'utf8');
  const hasVerifyJWT = jwtContent.includes('verifyJWT');
  const hasLogin = jwtContent.includes('login') || jwtContent.includes('/login');
  const hasRegister = jwtContent.includes('register') || jwtContent.includes('/register');
  
  console.log(`   verifyJWT function: ${hasVerifyJWT ? '✅ FOUND' : '❌ MISSING'}`);
  console.log(`   Login route: ${hasLogin ? '✅ FOUND' : '❌ MISSING'}`);
  console.log(`   Register route: ${hasRegister ? '✅ FOUND' : '❌ MISSING'}`);
} else {
  console.log('❌ jwt_router.js not found');
  console.log('⚠️  ACTION REQUIRED: Create routes/jwt_router.js with JWT authentication');
}

// Check 5: Scan route files for Firebase code
console.log('\n✅ CHECK 5: Scanning Route Files for Firebase Code');
console.log('─'.repeat(70));

const routesDir = path.join(process.cwd(), 'routes');
if (fs.existsSync(routesDir)) {
  const routeFiles = fs.readdirSync(routesDir).filter(f => f.endsWith('.js'));
  
  let totalFirebaseReferences = 0;
  let filesWithFirebase = [];
  
  routeFiles.forEach(file => {
    const filePath = path.join(routesDir, file);
    const content = fs.readFileSync(filePath, 'utf8');
    
    const firebaseImport = (content.match(/require\(['"]firebase-admin['"]\)/g) || []).length;
    const uidUsage = (content.match(/req\.user\.uid/g) || []).length;
    const customClaims = (content.match(/customClaims/g) || []).length;
    const uidQuery = (content.match(/\{\s*uid\s*:/g) || []).length;
    
    const totalInFile = firebaseImport + uidUsage + customClaims + uidQuery;
    
    if (totalInFile > 0) {
      totalFirebaseReferences += totalInFile;
      filesWithFirebase.push({
        file,
        firebaseImport,
        uidUsage,
        customClaims,
        uidQuery,
        total: totalInFile
      });
    }
  });
  
  if (filesWithFirebase.length === 0) {
    console.log('✅ No Firebase code found in route files!');
  } else {
    console.log(`⚠️  Found Firebase code in ${filesWithFirebase.length} files:\n`);
    
    filesWithFirebase.sort((a, b) => b.total - a.total).forEach(item => {
      console.log(`   📄 ${item.file} (${item.total} issues)`);
      if (item.firebaseImport > 0) console.log(`      - Firebase import: ${item.firebaseImport}`);
      if (item.uidUsage > 0) console.log(`      - req.user.uid: ${item.uidUsage}`);
      if (item.customClaims > 0) console.log(`      - customClaims: ${item.customClaims}`);
      if (item.uidQuery > 0) console.log(`      - {uid:...} queries: ${item.uidQuery}`);
    });
    
    console.log(`\n   Total Firebase references: ${totalFirebaseReferences}`);
  }
}

// Check 6: Common route patterns
console.log('\n✅ CHECK 6: Route Protection Analysis');
console.log('─'.repeat(70));

if (fs.existsSync(serverPath)) {
  const serverContent = fs.readFileSync(serverPath, 'utf8');
  
  // Count protected routes
  const protectedRoutes = (serverContent.match(/verifyJWT,/g) || []).length;
  const totalRoutes = (serverContent.match(/app\.use\(['"]\//g) || []).length;
  
  console.log(`Total route mounts: ${totalRoutes}`);
  console.log(`Protected with JWT: ${protectedRoutes}`);
  console.log(`Potentially unprotected: ${totalRoutes - protectedRoutes}`);
  
  if (protectedRoutes === 0) {
    console.log('\n⚠️  WARNING: No routes appear to use JWT middleware!');
    console.log('   Check that routes use verifyJWT middleware');
  }
}

// Final Summary
console.log('\n' + '═'.repeat(70));
console.log('📋 SUMMARY & NEXT STEPS');
console.log('═'.repeat(70));

console.log('\n1️⃣  IMMEDIATE ACTIONS:');
console.log('   □ Ensure JWT_SECRET is in .env file');
console.log('   □ Install required packages (jsonwebtoken, bcryptjs)');
console.log('   □ Remove firebase-admin from package.json');
console.log('   □ Create/verify jwt_router.js exists');

console.log('\n2️⃣  CODE FIXES:');
console.log('   □ Replace req.user.uid → req.user.email or req.user.userId');
console.log('   □ Replace {uid: ...} → {email: ...} in database queries');
console.log('   □ Replace customClaims → req.user.role');
console.log('   □ Add verifyJWT middleware to all protected routes');

console.log('\n3️⃣  TESTING:');
console.log('   □ Run: node test-all-endpoints.js');
console.log('   □ Test login endpoint first');
console.log('   □ Test each category of endpoints');
console.log('   □ Check server logs for errors');

console.log('\n4️⃣  FLUTTER APP:');
console.log('   □ Remove Firebase packages');
console.log('   □ Implement JWT token storage');
console.log('   □ Update all API calls to include JWT token');
console.log('   □ Update login flow to use /api/auth/login');

console.log('\n📚 For detailed fixes, see: firebase-removal-fix-guide.md');
console.log('🧪 To test endpoints, run: node test-all-endpoints.js');
console.log('');
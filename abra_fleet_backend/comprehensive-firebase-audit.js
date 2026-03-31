// comprehensive-firebase-audit.js - Complete Firebase removal audit
const fs = require('fs');
const path = require('path');

async function comprehensiveFirebaseAudit() {
  console.log('\n🔍 COMPREHENSIVE FIREBASE REMOVAL AUDIT');
  console.log('═'.repeat(80));
  
  const firebasePatterns = [
    // Firebase imports and requires
    /require\(['"`]firebase[/'"`]/gi,
    /import.*firebase/gi,
    /from ['"`]firebase/gi,
    
    // Firebase Admin SDK
    /firebase-admin/gi,
    /admin\.auth\(\)/gi,
    /admin\.firestore\(\)/gi,
    
    // Firebase Auth methods
    /verifyIdToken/gi,
    /createCustomToken/gi,
    /getAuth\(\)/gi,
    /signInWith/gi,
    /onAuthStateChanged/gi,
    
    // Firebase Firestore
    /firestore\(\)/gi,
    /\.collection\(/gi,
    /\.doc\(/gi,
    /\.add\(/gi,
    /\.set\(/gi,
    /\.update\(/gi,
    /\.delete\(/gi,
    /\.get\(/gi,
    /\.where\(/gi,
    
    // Firebase UID references
    /firebaseUid/gi,
    /firebase_uid/gi,
    /uid:/gi,
    /req\.user\.uid/gi,
    
    // Firebase config
    /serviceAccountKey/gi,
    /FIREBASE_/gi,
    /firebase.*config/gi,
    
    // Firebase Storage
    /firebase.*storage/gi,
    /getStorage/gi,
    
    // Firebase Realtime Database
    /firebase.*database/gi,
    /getDatabase/gi,
    
    // Firebase Cloud Messaging
    /firebase.*messaging/gi,
    /getMessaging/gi
  ];
  
  const excludePatterns = [
    /node_modules/,
    /\.git/,
    /\.env/,
    /package-lock\.json/,
    /\.log$/,
    /\.md$/,
    /test.*firebase/i, // Test files that mention firebase for testing
    /debug.*firebase/i, // Debug files
    /fix.*firebase/i, // Fix files
    /check.*firebase/i, // Check files
    /firebase.*rules/i // Firebase rules files (legacy)
  ];
  
  function shouldExcludeFile(filePath) {
    return excludePatterns.some(pattern => pattern.test(filePath));
  }
  
  function scanDirectory(dir, results = []) {
    const files = fs.readdirSync(dir);
    
    for (const file of files) {
      const filePath = path.join(dir, file);
      const stat = fs.statSync(filePath);
      
      if (stat.isDirectory()) {
        if (!shouldExcludeFile(filePath)) {
          scanDirectory(filePath, results);
        }
      } else if (stat.isFile()) {
        if (!shouldExcludeFile(filePath) && 
            (filePath.endsWith('.js') || 
             filePath.endsWith('.ts') || 
             filePath.endsWith('.json'))) {
          results.push(filePath);
        }
      }
    }
    
    return results;
  }
  
  console.log('📂 Scanning backend files for Firebase references...');
  const backendFiles = scanDirectory('./');
  
  console.log(`   Found ${backendFiles.length} files to scan`);
  
  const firebaseReferences = [];
  let totalFiles = 0;
  let filesWithFirebase = 0;
  
  for (const filePath of backendFiles) {
    try {
      const content = fs.readFileSync(filePath, 'utf8');
      totalFiles++;
      
      let fileHasFirebase = false;
      const fileReferences = [];
      
      for (const pattern of firebasePatterns) {
        const matches = content.match(pattern);
        if (matches) {
          fileHasFirebase = true;
          matches.forEach(match => {
            // Get line number
            const lines = content.split('\n');
            let lineNumber = 0;
            for (let i = 0; i < lines.length; i++) {
              if (lines[i].includes(match)) {
                lineNumber = i + 1;
                break;
              }
            }
            
            fileReferences.push({
              match: match,
              line: lineNumber,
              context: lines[lineNumber - 1]?.trim() || ''
            });
          });
        }
      }
      
      if (fileHasFirebase) {
        filesWithFirebase++;
        firebaseReferences.push({
          file: filePath,
          references: fileReferences
        });
      }
      
    } catch (error) {
      console.log(`   ⚠️  Could not read file: ${filePath}`);
    }
  }
  
  console.log('\n📊 AUDIT RESULTS:');
  console.log('─'.repeat(50));
  console.log(`   Total files scanned: ${totalFiles}`);
  console.log(`   Files with Firebase references: ${filesWithFirebase}`);
  
  if (firebaseReferences.length === 0) {
    console.log('\n✅ NO FIREBASE REFERENCES FOUND!');
    console.log('   The backend is completely free of Firebase dependencies.');
  } else {
    console.log('\n❌ FIREBASE REFERENCES FOUND:');
    console.log('─'.repeat(50));
    
    firebaseReferences.forEach((fileRef, index) => {
      console.log(`\n${index + 1}. 📄 ${fileRef.file}`);
      fileRef.references.forEach(ref => {
        console.log(`   Line ${ref.line}: ${ref.match}`);
        console.log(`   Context: ${ref.context}`);
      });
    });
    
    console.log('\n🔧 RECOMMENDED ACTIONS:');
    console.log('─'.repeat(30));
    console.log('1. Review each file with Firebase references');
    console.log('2. Replace Firebase auth with JWT authentication');
    console.log('3. Replace Firestore calls with MongoDB operations');
    console.log('4. Remove Firebase imports and configurations');
    console.log('5. Update environment variables');
  }
  
  // Check specific critical files
  console.log('\n🎯 CRITICAL FILES CHECK:');
  console.log('─'.repeat(30));
  
  const criticalFiles = [
    './index.js',
    './start-server.js',
    './routes/jwt_router.js',
    './middleware/auth.js',
    './routes/auth.js'
  ];
  
  for (const criticalFile of criticalFiles) {
    if (fs.existsSync(criticalFile)) {
      const content = fs.readFileSync(criticalFile, 'utf8');
      const hasFirebase = firebasePatterns.some(pattern => pattern.test(content));
      
      console.log(`   ${criticalFile}: ${hasFirebase ? '❌ HAS FIREBASE' : '✅ CLEAN'}`);
    } else {
      console.log(`   ${criticalFile}: ⚠️  FILE NOT FOUND`);
    }
  }
  
  // Check package.json for Firebase dependencies
  console.log('\n📦 PACKAGE DEPENDENCIES CHECK:');
  console.log('─'.repeat(30));
  
  if (fs.existsSync('./package.json')) {
    const packageJson = JSON.parse(fs.readFileSync('./package.json', 'utf8'));
    const dependencies = { ...packageJson.dependencies, ...packageJson.devDependencies };
    
    const firebaseDeps = Object.keys(dependencies).filter(dep => 
      dep.includes('firebase') || dep.includes('firestore')
    );
    
    if (firebaseDeps.length === 0) {
      console.log('   ✅ No Firebase dependencies found in package.json');
    } else {
      console.log('   ❌ Firebase dependencies found:');
      firebaseDeps.forEach(dep => {
        console.log(`     - ${dep}: ${dependencies[dep]}`);
      });
    }
  }
  
  console.log('\n═'.repeat(80));
  
  return {
    totalFiles,
    filesWithFirebase,
    firebaseReferences,
    isClean: firebaseReferences.length === 0
  };
}

// Run the audit
if (require.main === module) {
  comprehensiveFirebaseAudit().catch(console.error);
}

module.exports = { comprehensiveFirebaseAudit };
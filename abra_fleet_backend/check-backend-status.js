// check-backend-status.js - Quick script to check if backend is running

const http = require('http');

const checkBackend = (host, port) => {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: host,
      port: port,
      path: '/health',
      method: 'GET',
      timeout: 5000
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        resolve({
          status: res.statusCode,
          data: data,
          success: res.statusCode === 200
        });
      });
    });

    req.on('error', (err) => {
      reject(err);
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    req.end();
  });
};

async function main() {
  console.log('🔍 Checking backend server status...\n');

  const servers = [
    { name: 'Localhost (Web)', host: 'localhost', port: 3001 },
    { name: 'Local Network (Mobile)', host: '192.168.1.2', port: 3001 }
  ];

  for (const server of servers) {
    try {
      console.log(`Checking ${server.name} (${server.host}:${server.port})...`);
      const result = await checkBackend(server.host, server.port);
      
      if (result.success) {
        console.log(`✅ ${server.name}: Server is running`);
        console.log(`   Status: ${result.status}`);
        console.log(`   Response: ${result.data.substring(0, 100)}${result.data.length > 100 ? '...' : ''}`);
      } else {
        console.log(`⚠️  ${server.name}: Server responded with status ${result.status}`);
        console.log(`   Response: ${result.data}`);
      }
    } catch (error) {
      console.log(`❌ ${server.name}: ${error.message}`);
      
      if (error.code === 'ECONNREFUSED') {
        console.log(`   → Server is not running on ${server.host}:${server.port}`);
      } else if (error.code === 'ENOTFOUND') {
        console.log(`   → Host ${server.host} not found`);
      } else if (error.message === 'Request timeout') {
        console.log(`   → Server is not responding (timeout)`);
      }
    }
    console.log('');
  }

  console.log('💡 To start the backend server:');
  console.log('   cd abra_fleet_backend');
  console.log('   node index.js');
  console.log('');
  console.log('💡 To check if MongoDB is running:');
  console.log('   mongosh --eval "db.adminCommand(\'ping\')"');
}

main().catch(console.error);
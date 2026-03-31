const WebSocket = require('ws');
require('dotenv').config();

console.log('🧪 Testing WebSocket Connection Fix...\n');

// Test 1: Connection without tripId (should work now)
console.log('1. Testing connection without tripId...');
const ws1 = new WebSocket('ws://localhost:3001');

ws1.on('open', function open() {
  console.log('✅ Connected without tripId - SUCCESS');
  
  // Send a test message
  ws1.send(JSON.stringify({
    type: 'STATUS_UPDATE',
    data: { status: 'testing' },
    messageId: 'test-1'
  }));
  
  // Close after sending
  setTimeout(() => ws1.close(), 1000);
});

ws1.on('message', function message(data) {
  const msg = JSON.parse(data);
  console.log('📨 Received (no tripId):', msg.type, msg.data);
});

ws1.on('error', function error(err) {
  console.log('❌ Error without tripId:', err.message);
});

ws1.on('close', function close() {
  console.log('🔌 Connection closed (without tripId)');
});

// Test 2: Connection with tripId (should also work)
setTimeout(() => {
  console.log('\n2. Testing connection with tripId...');
  const ws2 = new WebSocket('ws://localhost:3001?tripId=test-trip-123');

  ws2.on('open', function open() {
    console.log('✅ Connected with tripId - SUCCESS');
    
    // Send a test message
    ws2.send(JSON.stringify({
      type: 'LOCATION_UPDATE',
      data: { latitude: 12.9716, longitude: 77.5946 },
      messageId: 'test-2'
    }));
    
    // Close after sending
    setTimeout(() => ws2.close(), 1000);
  });

  ws2.on('message', function message(data) {
    const msg = JSON.parse(data);
    console.log('📨 Received (with tripId):', msg.type, msg.data);
  });

  ws2.on('error', function error(err) {
    console.log('❌ Error with tripId:', err.message);
  });

  ws2.on('close', function close() {
    console.log('🔌 Connection closed (with tripId)');
  });
}, 3000);

// Exit after tests
setTimeout(() => {
  console.log('\n✅ WebSocket fix test completed!');
  process.exit(0);
}, 8000);

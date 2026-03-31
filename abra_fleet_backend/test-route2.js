// Test what's being exported from the test file
const route = require('./routes/admin-clients-unified-test');
console.log('Type:', typeof route);
console.log('Constructor:', route.constructor.name);
console.log('Is function:', typeof route === 'function');
console.log('Has router methods:', typeof route.get === 'function', typeof route.post === 'function');
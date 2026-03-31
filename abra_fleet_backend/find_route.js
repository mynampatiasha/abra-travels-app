const fs = require('fs');
const path = require('path');

const filesToSearch = [
    'routes/roster_router.js',
    'routes/route_optimization_router.js'
];

filesToSearch.forEach(file => {
    try {
        const content = fs.readFileSync(path.join(__dirname, file), 'utf8');
        const lines = content.split('\n');

        console.log(`\nScanning ${file}...`);
        let found = false;
        lines.forEach((line, index) => {
            if (line.includes('group-similar') || line.includes('group_similar')) {
                console.log(`Line ${index + 1}: ${line.trim()}`);
                found = true;
            }
        });

        if (!found) {
            console.log('Not found.');
        }
    } catch (err) {
        console.error(`Error reading ${file}: ${err.message}`);
    }
});

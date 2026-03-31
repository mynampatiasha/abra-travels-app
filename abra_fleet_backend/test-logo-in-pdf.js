// Test if logo can be loaded into PDF
const PDFDocument = require('pdfkit');
const fs = require('fs');
const path = require('path');

console.log('Testing logo in PDF generation...\n');

const logoPath = path.join(__dirname, 'assets', 'abra-travels-logo.png');
const outputPath = path.join(__dirname, 'uploads', 'invoices', 'test-logo-output.pdf');

// Ensure output directory exists
const outputDir = path.dirname(outputPath);
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
  console.log('Created output directory');
}

console.log('Logo path:', logoPath);
console.log('Output path:', outputPath);
console.log('Logo exists:', fs.existsSync(logoPath), '\n');

if (!fs.existsSync(logoPath)) {
  console.log('ERROR: Logo file not found!');
  process.exit(1);
}

// Create PDF
const doc = new PDFDocument({ size: 'A4', margin: 50 });
const stream = fs.createWriteStream(outputPath);

doc.pipe(stream);

try {
  // Try to add logo
  console.log('Attempting to add logo to PDF...');
  doc.image(logoPath, 50, 45, { width: 180, height: 90 });
  console.log('SUCCESS: Logo added to PDF!\n');
  
  // Add some text
  doc.fontSize(20)
     .fillColor('#0066CC')
     .text('ABRA Travels Logo Test', 50, 150);
  
  doc.fontSize(12)
     .fillColor('#000000')
     .text('If you see the logo above, it is working correctly!', 50, 200);
  
  doc.end();
  
  stream.on('finish', () => {
    console.log('PDF generated successfully!');
    console.log('Open this file to verify logo appears:');
    console.log(outputPath);
    console.log('\nIf logo appears in this test PDF, then:');
    console.log('1. Restart your backend server');
    console.log('2. Generate a new invoice');
    console.log('3. Logo should appear in invoice PDFs');
  });
  
  stream.on('error', (err) => {
    console.error('ERROR writing PDF:', err.message);
  });
  
} catch (error) {
  console.error('ERROR adding logo to PDF:', error.message);
  console.error('\nPossible causes:');
  console.error('- Image file is corrupted');
  console.error('- Unsupported image format');
  console.error('- PDFKit version issue');
  process.exit(1);
}

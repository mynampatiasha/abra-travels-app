<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php'); // Assuming the correct database connection file

// Get the business filter from URL (GET)
$b = isset($_GET['b']) ? $_GET['b'] : '';

if($b == "at"){
    $business = 'Abra Travels';
}
elseif($b == "db"){
    $business = 'Abra Designbuild';
}
elseif($b == "al"){
    $business = 'Abra Logistics';
}
else{
    $business = 'Abra Travels';
}

// Query to fetch vendor data based on the business type
$query = "SELECT * FROM vendors";
if ($business) {
    $query .= " WHERE business = '$business'";
}

$result = mysqli_query($dbConn, $query);

// Set Excel headers
header('Content-Type: application/vnd.ms-excel');
header('Content-Disposition: attachment;filename="vendors_'.$business.'.xls"');
header('Cache-Control: max-age=0');

// Output the table headers
$headers = [
    "Vendor ID", "Vendor Name", "Concerned Person", "Email", "Phone", "Address", 
    "GST Details", "Bank Account", "Vendor Category", "Contract Number", 
    "Contract Start Date", "Contract End Date", "Contract Renewal Date", 
    "Contract Status", "Subcategories", "Subsubcategories", "Business Type", 
    "Services Offered", "Business"
];
echo implode("\t", $headers) . "\n";

// Output vendor data
while ($row = mysqli_fetch_assoc($result)) {
    // Prepare each field and escape commas by enclosing in double quotes
    $data = [
        $row['vendor_id'], 
        '"' . str_replace('"', '""', $row['vendor_name']) . '"',
        '"' . str_replace('"', '""', $row['concerned_person']) . '"',
        '"' . str_replace('"', '""', $row['email']) . '"',
        '"' . str_replace('"', '""', $row['phone']) . '"',
        '"' . str_replace('"', '""', $row['address']) . '"',
        '"' . str_replace('"', '""', $row['gst_details']) . '"',
        '"' . str_replace('"', '""', $row['bank_account']) . '"',
        '"' . str_replace('"', '""', $row['vendor_category']) . '"',
        '"' . str_replace('"', '""', $row['contract_number']) . '"',
        '"' . str_replace('"', '""', $row['contract_start_date']) . '"',
        '"' . str_replace('"', '""', $row['contract_end_date']) . '"',
        '"' . str_replace('"', '""', $row['contract_renewal_date']) . '"',
        '"' . str_replace('"', '""', $row['contract_status']) . '"',
        '"' . str_replace('"', '""', $row['subcategories']) . '"',
        '"' . str_replace('"', '""', $row['subsubcategories']) . '"',
        '"' . str_replace('"', '""', $row['business_type']) . '"',
        '"' . str_replace('"', '""', $row['services_offered']) . '"',
        '"' . str_replace('"', '""', $row['business']) . '"'
    ];
    echo implode("\t", $data) . "\n";
}

mysqli_close($dbConn);
exit;
?>

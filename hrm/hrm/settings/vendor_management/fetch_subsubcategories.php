<?php
session_start();
require_once('../../database.php');

$data = json_decode(file_get_contents("php://input"), true);

// Validate input
if (!isset($data['subcategories']) || empty($data['subcategories'])) {
    echo json_encode([]);
    exit;
}

$subcategories = $data['subcategories'];
if (!is_array($subcategories)) {
    echo json_encode([]);
    exit;
}

// Safely escape the subcategories
$subcategories = array_map('mysqli_real_escape_string', array_fill(0, count($subcategories), $dbConn), $subcategories);
$subcategoryList = "'" . implode("','", $subcategories) . "'";

// Query to fetch sub-subcategories
$query = "SELECT DISTINCT(sub_category_2) FROM vendor_categories WHERE sub_category_1 IN ($subcategoryList)";

$result = mysqli_query($dbConn, $query);
if (!$result) {
    echo json_encode([]);
    exit;
}

$subsubcategories = [];
while ($row = mysqli_fetch_assoc($result)) {
    $subsubcategories[] = $row['sub_category_2'];
}

// Return the sub-subcategories as a JSON array
echo json_encode($subsubcategories);
?>

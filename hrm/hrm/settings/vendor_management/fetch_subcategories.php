<?php
session_start();
require_once('../../database.php');

$data = json_decode(file_get_contents("php://input"), true);

if (!isset($data['categories']) || empty($data['categories'])) {
    echo json_encode([]);
    exit;
}

$categories = $data['categories'];
if (!is_array($categories)) {
    echo json_encode([]);
    exit;
}

$categories = array_map('mysqli_real_escape_string', array_fill(0, count($categories), $dbConn), $categories);
$categoryList = "'" . implode("','", $categories) . "'";
$query = "SELECT DISTINCT(sub_category_1) FROM vendor_categories WHERE category IN ($categoryList)";

$result = mysqli_query($dbConn, $query);
if (!$result) {
    echo json_encode([]);
    exit;
}

$subcategories = [];
while ($row = mysqli_fetch_assoc($result)) {
    $subcategories[] = $row['sub_category_1'];
}

echo json_encode($subcategories);
?>

<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

session_start();
require_once('../../database.php');
require_once('../../database-settings.php');

$data = json_decode(file_get_contents('php://input'), true);

// Search item by barcode
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($data['barcode'])) {
    $barcode = mysqli_real_escape_string($dbConn, $data['barcode']);
    $query = "SELECT * FROM storage WHERE Item_Code = '$barcode'";
    $result = mysqli_query($dbConn, $query);

    if (mysqli_num_rows($result) > 0) {
        $item = mysqli_fetch_assoc($result);
        echo json_encode(["success" => true, "item" => $item]);
    } else {
        echo json_encode(["success" => false, "message" => "Item not found"]);
    }
    exit;
}

// Submit scanned items
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($data['items'])) {
    $items = $data['items'];
    
    // Fetch the last tracking number
    $lastTrackingQuery = "SELECT MAX(Tracking_No) as last_tracking FROM c_tracking";
    $lastTrackingResult = mysqli_query($dbConn, $lastTrackingQuery);
    $lastTrackingRow = mysqli_fetch_assoc($lastTrackingResult);
    $lastTracking = $lastTrackingRow['last_tracking'];
    $newTrackingNo = "TR" . (intval(substr($lastTracking, 2)) + 1);

    foreach ($items as $item) {
        $itemCode = mysqli_real_escape_string($dbConn, $item['Item_Code']);
        $itemName = mysqli_real_escape_string($dbConn, $item['Item_Name']);
        $query = "INSERT INTO fulfillment (Tracking_No, Item_Code, Item_Name) VALUES ('$newTrackingNo', '$itemCode', '$itemName')";
        mysqli_query($dbConn, $query);
    }

    echo json_encode(["success" => true, "message" => "Items submitted successfully!", "tracking_number" => $newTrackingNo]);
    exit;
}

// Fetch tracking number and order_id
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($data['fetchTrackingOrder'])) {
	$items = $data['fetchTrackingOrder'];
// Fetch the last tracking number		
$pa = mysqli_query($dbConn, "SELECT MAX(tracking_no) as maximo FROM fulfillment");
if ($row = mysqli_fetch_array($pa)) {
    if ($row['maximo'] == NULL) {
        $cons_no = 'ALFUL-1000001';
    } else {
        // Extract numeric part
        $numericPart = intval(substr($row['maximo'], 6)); // Skip 'ALFUL-' prefix
        $cons_no = 'ALFUL-' . ($numericPart + 1);
    }
}
$newTrackingNo = $cons_no;

// Fetch the last order ID
// Fetch the last order ID
$lastOrderIdQuery = "SELECT order_id FROM fulfillment ORDER BY LENGTH(order_id) DESC, order_id DESC LIMIT 1";
$lastOrderIdResult = mysqli_query($dbConn, $lastOrderIdQuery);

if (!$lastOrderIdResult) {
    die(json_encode(["success" => false, "error" => "Query failed: " . mysqli_error($dbConn)]));
}

$newOrderId = 'OR-1000001'; // Default value for the first order
if ($row2 = mysqli_fetch_assoc($lastOrderIdResult)) {
    if (!empty($row2['order_id'])) {
        // Extract numeric part
        $numericPart = intval(substr($row2['order_id'], 3)); // Skip 'OR-' prefix
        $newOrderId = 'OR-' . ($numericPart + 1);
    }
}


echo json_encode(["trackingNo" => $newTrackingNo, "orderId" => $newOrderId]);
exit;

}

// Close connection
mysqli_close($dbConn);
?>

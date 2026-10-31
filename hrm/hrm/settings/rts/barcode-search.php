<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

session_start();
require_once('../../database.php'); // Database connection file
require_once('../../database-settings.php'); // Additional settings file

$data = json_decode(file_get_contents('php://input'), true);

// Search for tracking details by barcode
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($data['tracking_no'])) {
    $tracking_no = mysqli_real_escape_string($dbConn, $data['tracking_no']);
    
    // Query to fetch tracking details
    $query = "
        SELECT 
    f.tracking_no,
    f.order_id,
    f.customer_name,
    f.order_date,
    f.product_id,
    f.product_name,
    f.total_value AS order_value,
	f.order_date AS order_date,
    f.ordered_qty
FROM fulfillment f
WHERE f.tracking_no = '$tracking_no'

UNION ALL

SELECT 
    c.tracking AS tracking_no,
    '' AS order_id,
    c.rev_name AS customer_name,
    c.book_date AS order_date,
    '' AS product_id,
    '' AS product_name,
    '' AS order_value,
	c.book_date AS order_date,
    '' AS ordered_qty
FROM courier c
WHERE c.tracking = '$tracking_no'

UNION ALL

SELECT 
    a.tracking_no,
    a.order_id,
    a.customer_name,
    a.date_added AS order_date,
    '' AS product_id,
    '' AS product_name,
    a.total_amount AS order_value,
    a.date_added AS order_date,
    '' AS ordered_qty
FROM az_orders a
WHERE a.tracking_no = '$tracking_no'";
		

    
    $result = mysqli_query($dbConn, $query);
    
    if (!$result) {
        echo json_encode([
            "success" => false,
            "message" => "Database query error: " . mysqli_error($dbConn)
        ]);
        exit;
    }

    if (mysqli_num_rows($result) > 0) {
        $trackingDetails = mysqli_fetch_assoc($result);

        echo json_encode([
            "success" => true,
            "tracking_no" => $trackingDetails['tracking_no'],
            "order_id" => $trackingDetails['order_id'] ?? 'N/A',
            "customer_name" => $trackingDetails['customer_name'] ?? 'N/A',
            "product_id" => $trackingDetails['product_id'] ?? 'N/A',
            "product_name" => $trackingDetails['product_name'] ?? 'N/A',
            "ordered_qty" => $trackingDetails['ordered_qty'] ?? 'N/A',
            "order_value" => $trackingDetails['order_value'] ?? 'N/A',
            "order_date" => $trackingDetails['order_date'] ?? 'N/A',
            "scanned_by" => isset($_SESSION['user_name']) ? $_SESSION['user_name'] : null // Add 'scanned_by' field
        ]);
    } else {
        echo json_encode([
            "success" => false,
            "message" => "Tracking number not found in the database."
        ]);
    }
    exit;
}

// Handle any other cases or invalid requests
echo json_encode([
    "success" => false,
    "message" => "Invalid request."
]);
exit;

// Close the database connection
mysqli_close($dbConn);
?>
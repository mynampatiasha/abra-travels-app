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
            tracking_no, 
            delivery_date, 
            NULL AS origin, 
            NULL AS destination 
        FROM fulfillment 
        WHERE tracking_no = '$tracking_no'
        UNION
        SELECT 
            tracking AS tracking_no, 
            schedule AS delivery_date, 
            s_add AS origin, 
            r_add AS destination 
        FROM courier 
        WHERE tracking = '$tracking_no'
		UNION
        SELECT 
            tracking_no, 
            date_added AS delivery_date, 
            'Abra Zylo' AS origin, 
            shipping_address AS destination 
        FROM az_orders 
        WHERE tracking_no = '$tracking_no'";
    
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
            "origin" => $trackingDetails['origin'] ?? 'N/A',
            "destination" => $trackingDetails['destination'] ?? 'N/A',
            "delivery_date" => $trackingDetails['delivery_date'] ?? 'N/A',
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

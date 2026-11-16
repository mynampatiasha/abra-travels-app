<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once('../../database.php'); // Include your database connection
require_once('../../database-settings.php'); // Additional settings file

$data = json_decode(file_get_contents('php://input'), true);

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($data['tracking_numbers'])) {
    $trackingNumbers = $data['tracking_numbers'];

    // Escape and prepare tracking numbers for query
    $escapedTrackingNumbers = array_map(function($tracking) use ($dbConn) {
        return "'" . mysqli_real_escape_string($dbConn, $tracking) . "'";
    }, $trackingNumbers);

    $placeholders = implode(',', $escapedTrackingNumbers);

    $query = "SELECT 
                tracking_no, 
                company_name, 
                customer_code, 
                customer_name, 
                order_date
              FROM fulfillment 
              WHERE tracking_no IN ($placeholders)
				UNION
					SELECT 
						tracking, 
						ship_name, 
						cid, 
						ship_name,
						book_date
					FROM courier 
					WHERE tracking IN ($placeholders)
						UNION
						SELECT 
							tracking_no, 
							customer_name, 
							id, 
							customer_name,
							date_added
						FROM az_orders 
						WHERE tracking_no IN ($placeholders)";

    $result = mysqli_query($dbConn, $query);

    if ($result) {
        $orders = [];

        while ($row = mysqli_fetch_assoc($result)) {
            $orders[] = $row;
        }

        echo json_encode(["success" => true, "orders" => $orders]);
    } else {
        echo json_encode(["success" => false, "message" => "Database query failed.", "error" => mysqli_error($dbConn)]);
    }

    exit;
}

// Handle invalid requests
echo json_encode(["success" => false, "message" => "Invalid request."]);
exit;
?>

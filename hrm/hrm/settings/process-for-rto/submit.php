<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

session_start();
require_once('../../database.php');
require_once('../../database-settings.php');

header('Content-Type: application/json'); // Set response to JSON

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);

    if ($input['action'] === 'submit' && isset($input['data']) && is_array($input['data'])) {
        $data = $input['data'];
        $values = [];

        foreach ($data as $row) {
            $tracking_no = mysqli_real_escape_string($dbConn, $row['tracking_no']);
            $order_id = mysqli_real_escape_string($dbConn, $row['order_id']);
            $order_date = mysqli_real_escape_string($dbConn, $row['order_date']);
            $rto_initiation_date = mysqli_real_escape_string($dbConn, $row['rto_initiation_date']);
            $customer_name = mysqli_real_escape_string($dbConn, $row['customer_name']);
            $rto_reason = mysqli_real_escape_string($dbConn, $row['rto_reason']);
            $rto_status = mysqli_real_escape_string($dbConn, $row['rto_status']);
            $carrier_name = mysqli_real_escape_string($dbConn, $row['carrier_name']);
            $rto_tracking_no = mysqli_real_escape_string($dbConn, $row['rto_tracking_no']);
            $product_id = mysqli_real_escape_string($dbConn, $row['product_id']);
            $product_name = mysqli_real_escape_string($dbConn, $row['product_name']);
            $ordered_qty = mysqli_real_escape_string($dbConn, $row['ordered_qty']);
            $returned_qty = mysqli_real_escape_string($dbConn, $row['returned_qty']);
            $product_condition = mysqli_real_escape_string($dbConn, $row['product_condition']);
            $refund_status = mysqli_real_escape_string($dbConn, $row['refund_status']);
            $stock_status = mysqli_real_escape_string($dbConn, $row['stock_status']);
            $remarks = mysqli_real_escape_string($dbConn, $row['remarks']);
			
			if (!empty($tracking_no)) {
				$status = 'Process for RTO';

				if (preg_match('/^AL-\d+$/', $tracking_no)) {
					$updateQuery = "UPDATE courier SET status='$status' WHERE tracking='$tracking_no'";
					mysqli_query($dbConn, $updateQuery);
				} elseif (preg_match('/^ALFUL-\d+$/', $tracking_no)) {
					$updateQuery = "UPDATE fulfillment SET order_status='$status' WHERE tracking_no='$tracking_no'";
					mysqli_query($dbConn, $updateQuery);
				} elseif (preg_match('/^AZ-\d+$/', $tracking_no)) {
					$statusQuery = "SELECT order_status_id FROM oc_order_status WHERE name='$status'";
					$result = mysqli_query($dbConnZylo, $statusQuery);
					if ($row = mysqli_fetch_assoc($result)) {
						$order_status_id = $row['order_status_id'];
						$updateQuery1 = "UPDATE oc_order SET order_status_id='$order_status_id' WHERE order_id='$order_id'";
						mysqli_query($dbConnZylo, $updateQuery1);
						$updateQuery2 = "UPDATE az_orders SET order_status='$order_status_id' WHERE tracking_no='$tracking_no'";
						mysqli_query($dbConn, $updateQuery2);
					} else {
						error_log("Order status ID not found for status: $status");
					}
				}
			}

            // Prepare values for insertion into the process_for_rto table
            $values[] = "('$tracking_no', '$order_id', '$order_date', '$rto_initiation_date', '$customer_name', '$rto_reason', '$rto_status', '$carrier_name', '$rto_tracking_no', '$product_id', '$product_name', '$ordered_qty', '$returned_qty', '$product_condition', '$refund_status', '$stock_status', '$remarks')";
        }

        $query = "INSERT INTO process_for_rto (tracking_no, order_id, order_date, rto_initiation_date, customer_name, rto_reason, rto_status, carrier_name, rto_tracking_no, product_id, product_name, ordered_qty, returned_qty, product_condition, refund_status, stock_status, remarks) VALUES " . implode(", ", $values);

        mysqli_begin_transaction($dbConn); // Start a transaction
        try {
            // Insert records into the process_for_rto table
            if (!mysqli_query($dbConn, $query)) {
                throw new Exception("Database error: " . mysqli_error($dbConn));
            }

            mysqli_commit($dbConn); // Commit the transaction
            echo json_encode(['success' => true, 'message' => 'Records inserted successfully.']);
        } catch (Exception $e) {
            mysqli_rollback($dbConn); // Rollback transaction in case of error
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
    } else {
        echo json_encode(['success' => false, 'message' => 'Invalid data format.']);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Invalid request method.']);
}
?>

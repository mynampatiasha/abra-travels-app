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
            $customer_name = mysqli_real_escape_string($dbConn, $row['customer_name']);
            $order_date = mysqli_real_escape_string($dbConn, $row['order_date']);
            $shipment_cancel_date = mysqli_real_escape_string($dbConn, $row['shipment_cancel_date']);
            $cancellation_reason = mysqli_real_escape_string($dbConn, $row['cancellation_reason']);
            $product_id = mysqli_real_escape_string($dbConn, $row['product_id']);
            $product_name = mysqli_real_escape_string($dbConn, $row['product_name']);
            $ordered_qty = mysqli_real_escape_string($dbConn, $row['ordered_qty']);
            $canceled_qty = mysqli_real_escape_string($dbConn, $row['canceled_qty']);
            $carrier_name = mysqli_real_escape_string($dbConn, $row['carrier_name']);
            $shipment_status = mysqli_real_escape_string($dbConn, $row['shipment_status']);
            $return_to_stock = mysqli_real_escape_string($dbConn, $row['return_to_stock']);
            $order_value = mysqli_real_escape_string($dbConn, $row['order_value']);
            $refund_status = mysqli_real_escape_string($dbConn, $row['refund_status']);
            $refund_amount = mysqli_real_escape_string($dbConn, $row['refund_amount']);
            $payment_method = mysqli_real_escape_string($dbConn, $row['payment_method']);
            $cancellation_charges = mysqli_real_escape_string($dbConn, $row['cancellation_charges']);
            $remarks = mysqli_real_escape_string($dbConn, $row['remarks']);
			
			if (!empty($tracking_no)) {
				$status = 'Cancel Shipment';

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

            // Prepare values for insertion into the canceled_shipments table
            $values[] = "('$tracking_no', '$order_id', '$customer_name', '$order_date', '$shipment_cancel_date', '$cancellation_reason', '$product_id', '$product_name', '$ordered_qty', '$canceled_qty', '$carrier_name', '$shipment_status', '$return_to_stock', '$order_value', '$refund_status', '$refund_amount', '$payment_method', '$cancellation_charges', '$remarks')";
        }

        $query = "INSERT INTO canceled_shipments (tracking_no, order_id, customer_name, order_date, shipment_cancel_date, cancellation_reason, product_id, product_name, ordered_qty, canceled_qty, carrier_name, shipment_status, return_to_stock, order_value, refund_status, refund_amount, payment_method, cancellation_charges, remarks) VALUES " . implode(", ", $values);

        mysqli_begin_transaction($dbConn); // Start a transaction
        try {
            // Insert records into the canceled_shipments table
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

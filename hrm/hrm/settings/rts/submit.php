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
            $return_request_date = mysqli_real_escape_string($dbConn, $row['return_request_date']);
            $return_status = mysqli_real_escape_string($dbConn, $row['return_status']);
            $return_reason = mysqli_real_escape_string($dbConn, $row['return_reason']);
            $product_id = mysqli_real_escape_string($dbConn, $row['product_id']);
            $product_name = mysqli_real_escape_string($dbConn, $row['product_name']);
            $ordered_qty = mysqli_real_escape_string($dbConn, $row['ordered_qty']);
            $returned_qty = mysqli_real_escape_string($dbConn, $row['returned_qty']);
            $condition_of_product = mysqli_real_escape_string($dbConn, $row['condition_of_product']);
            $return_tracking_no = mysqli_real_escape_string($dbConn, $row['return_tracking_no']);
            $return_carrier = mysqli_real_escape_string($dbConn, $row['return_carrier']);
            $return_shipping_date = mysqli_real_escape_string($dbConn, $row['return_shipping_date']);
            $return_received_date = mysqli_real_escape_string($dbConn, $row['return_received_date']);
            $warehouse_received_by = mysqli_real_escape_string($dbConn, $row['warehouse_received_by']);
            $return_inspection_status = mysqli_real_escape_string($dbConn, $row['return_inspection_status']);
            $refund_status = mysqli_real_escape_string($dbConn, $row['refund_status']);
            $refund_amount = mysqli_real_escape_string($dbConn, $row['refund_amount']);
            $payment_method = mysqli_real_escape_string($dbConn, $row['payment_method']);
            $original_order_value = mysqli_real_escape_string($dbConn, $row['original_order_value']);
            $remarks = mysqli_real_escape_string($dbConn, $row['remarks']);

            if (!empty($tracking_no)) {
				$status = 'Return to Sender';

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

            // Prepare values for insertion into the returns table
            $values[] = "('$tracking_no', '$order_id', '$customer_name', '$order_date', '$return_request_date', '$return_status', '$return_reason', '$product_id', '$product_name', '$ordered_qty', '$returned_qty', '$condition_of_product', '$return_tracking_no', '$return_carrier', '$return_shipping_date', '$return_received_date', '$warehouse_received_by', '$return_inspection_status', '$refund_status', '$refund_amount', '$payment_method', '$original_order_value', '$remarks')";
        }

        $query = "INSERT INTO rts (tracking_no, order_id, customer_name, order_date, return_request_date, return_status, return_reason, product_id, product_name, ordered_qty, returned_qty, condition_of_product, return_tracking_no, return_carrier, return_shipping_date, return_received_date, warehouse_received_by, return_inspection_status, refund_status, refund_amount, payment_method, original_order_value, remarks) VALUES " . implode(", ", $values);

        mysqli_begin_transaction($dbConn);
        try {
            if (!mysqli_query($dbConn, $query)) {
                throw new Exception("Database error: " . mysqli_error($dbConn));
            }

            mysqli_commit($dbConn);
            echo json_encode(['success' => true, 'message' => 'Records inserted successfully.']);
        } catch (Exception $e) {
            mysqli_rollback($dbConn);
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
    } else {
        echo json_encode(['success' => false, 'message' => 'Invalid data format.']);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Invalid request method.']);
}
?>

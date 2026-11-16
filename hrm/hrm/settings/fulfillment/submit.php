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
        $updateQueries = [];

        foreach ($data as $row) {
            $tracking_no = mysqli_real_escape_string($dbConn, $row['tracking_no']);
            $company_name = mysqli_real_escape_string($dbConn, $row['company_name']);
            $customer_code = mysqli_real_escape_string($dbConn, $row['customer_code']);
            $customer_name = mysqli_real_escape_string($dbConn, $row['customer_name']);
            $category = mysqli_real_escape_string($dbConn, $row['category']);
            $order_id = mysqli_real_escape_string($dbConn, $row['order_id']);
            $product_id = mysqli_real_escape_string($dbConn, $row['product_id']);
            $product_name = mysqli_real_escape_string($dbConn, $row['product_name']);
            $order_date = mysqli_real_escape_string($dbConn, $row['order_date']);
            $origin = mysqli_real_escape_string($dbConn, $row['origin']);
            $destination = mysqli_real_escape_string($dbConn, $row['destination']);
            $delivery_date = mysqli_real_escape_string($dbConn, $row['delivery_date']);
            $ordered_qty = mysqli_real_escape_string($dbConn, $row['ordered_qty']);
            $fulfilled_qty = mysqli_real_escape_string($dbConn, $row['fulfilled_qty']);
            $backorder_qty = mysqli_real_escape_string($dbConn, $row['backorder_qty']);
            $current_stock = mysqli_real_escape_string($dbConn, $row['current_stock']);
            $shipping_method = mysqli_real_escape_string($dbConn, $row['shipping_method']);
            $order_status = mysqli_real_escape_string($dbConn, $row['order_status']);
            $reason = mysqli_real_escape_string($dbConn, $row['reason']);
            $unit_price = mysqli_real_escape_string($dbConn, $row['unit_price']);
            $total_value = mysqli_real_escape_string($dbConn, $row['total_value']);
            $payment_status = mysqli_real_escape_string($dbConn, $row['payment_status']);

            $values[] = "('$tracking_no', '$company_name', '$customer_code', '$customer_name', '$category', '$order_id', '$product_id', '$product_name', '$order_date', '$origin', '$destination', '$delivery_date', '$ordered_qty', '$fulfilled_qty', '$backorder_qty', '$current_stock', '$shipping_method', '$order_status', '$reason', '$unit_price', '$total_value', '$payment_status')";

            $updateQueries[] = "UPDATE storage SET current_qty = current_qty - $fulfilled_qty WHERE item_code = '$product_id'";
        }

        $query = "INSERT INTO fulfillment (tracking_no, company_name, customer_code, customer_name, category, order_id, product_id, product_name, order_date, origin, destination, delivery_date, ordered_qty, fulfilled_qty, backorder_qty, current_stock, shipping_method, order_status, reason, unit_price, total_value, payment_status) VALUES " . implode(", ", $values);

        mysqli_begin_transaction($dbConn); // Start a transaction
        try {
            // Insert fulfillment records
            if (!mysqli_query($dbConn, $query)) {
                throw new Exception("Database error: " . mysqli_error($dbConn));
            }

            // Update current_qty in storage table
            foreach ($updateQueries as $updateQuery) {
                if (!mysqli_query($dbConn, $updateQuery)) {
                    throw new Exception("Database error while updating storage: " . mysqli_error($dbConn));
                }
            }

            // Check and update OpenCart database
            foreach ($data as $row) {
				$fulfilled_qty = (int) $row['fulfilled_qty'];
				$product_name = mysqli_real_escape_string($dbConnZylo, $row['product_name']);

				// Fetch the product_id based on product_name
				$get_id_query = "SELECT pd.product_id 
								 FROM oc_product_description pd
								 INNER JOIN oc_product p ON pd.product_id = p.product_id
								 WHERE pd.name = '$product_name'";
				$get_id_result = mysqli_query($dbConnZylo, $get_id_query);

				if ($get_id_result && mysqli_num_rows($get_id_result) > 0) {
					$product_data = mysqli_fetch_assoc($get_id_result);
					$product_id = $product_data['product_id'];

					// Fetch the current quantity
					$opencartQuery = "SELECT quantity FROM oc_product WHERE product_id = '$product_id'";
					$opencartResult = mysqli_query($dbConnZylo, $opencartQuery);

					if ($opencartResult && mysqli_num_rows($opencartResult) > 0) {
						$opencartRow = mysqli_fetch_assoc($opencartResult);
						$newQuantity = max(0, (int) $opencartRow['quantity'] - $fulfilled_qty);

						// Update the quantity in oc_product
						$updateOpencartQuery = "UPDATE oc_product SET quantity = $newQuantity WHERE product_id = '$product_id'";
						if (!mysqli_query($dbConnZylo, $updateOpencartQuery)) {
							throw new Exception("Database error while updating OpenCart: " . mysqli_error($dbConnZylo));
						}
					}
				} 
			}

            mysqli_commit($dbConn); // Commit transaction
            echo json_encode(['success' => true, 'message' => 'Records inserted and stock updated successfully.']);
        } catch (Exception $e) {
            mysqli_rollback($dbConn); // Rollback transaction
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
    } else {
        echo json_encode(['success' => false, 'message' => 'Invalid data format.']);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Invalid request method.']);
}
?>

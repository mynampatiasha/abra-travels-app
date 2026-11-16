<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');
require_once('../../database-settings.php');

// Fetch POST data
$order_id = $_POST['order_id'] ?? 0;
$order_status_id = $_POST['order_status'] ?? 0;
$tracking_no = $_POST['tracking_no'] ?? 0;

if (!$order_id || !$order_status_id) {
    die("Invalid request");
}

// Fetch order details from OpenCart database
$sql_order = "SELECT * FROM `oc_order` WHERE `order_id` = ?";
$stmt_order = mysqli_prepare($dbConnZylo, $sql_order);
mysqli_stmt_bind_param($stmt_order, "i", $order_id);
mysqli_stmt_execute($stmt_order);
$result_order = mysqli_stmt_get_result($stmt_order);
$order = mysqli_fetch_assoc($result_order);

// Fetch products for the order
$sql_products = "SELECT * FROM `oc_order_product` WHERE order_id = ?";
$stmt_products = mysqli_prepare($dbConnZylo, $sql_products);
mysqli_stmt_bind_param($stmt_products, "i", $order_id);
mysqli_stmt_execute($stmt_products);
$result_products = mysqli_stmt_get_result($stmt_products);
$products = mysqli_fetch_all($result_products, MYSQLI_ASSOC);

// Save order details to CRM database
$sql_crm = "INSERT INTO `az_orders` (order_id, tracking_no, customer_name, email, phone, shipping_address, payment_method, products, order_status, total_amount, date_added)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE
            order_status = VALUES(order_status),
			total_amount = VALUES(total_amount)";
$stmt_crm = mysqli_prepare($dbConn, $sql_crm);

$customer_name = $order['firstname'] . ' ' . $order['lastname'];
$shipping_address = $order['shipping_address_1'] . ', ' . $order['shipping_address_2'] . ', ' . $order['shipping_city'] . ', ' . $order['shipping_zone'] . ', ' . $order['shipping_country'];
$products_json = json_encode($products); // Save products as JSON

mysqli_stmt_bind_param($stmt_crm, "isssssssss", $order_id, $tracking_no, $customer_name, $order['email'], $order['telephone'], $shipping_address, $order['payment_method'], $products_json, $order_status_id, $order['total']);
mysqli_stmt_execute($stmt_crm);

// Update order status in OpenCart database
$sql_oc = "UPDATE `oc_order` SET `order_status_id` = ? WHERE `order_id` = ?";
$stmt_oc = mysqli_prepare($dbConnZylo, $sql_oc);
mysqli_stmt_bind_param($stmt_oc, "ii", $order_status_id, $order_id);
mysqli_stmt_execute($stmt_oc);

// Add entry to oc_order_history
$sql_history = "INSERT INTO `oc_order_history` (order_id, order_status_id, notify, comment, date_added)
                VALUES (?, ?, 1, '', NOW())";
$stmt_history = mysqli_prepare($dbConnZylo, $sql_history);
mysqli_stmt_bind_param($stmt_history, "ii", $order_id, $order_status_id);
mysqli_stmt_execute($stmt_history);

echo "<script type=\"text/javascript\">
			alert(\"Updatd Successfully!\");
			window.location = \"../../abra-zylo-orders.php\"
		</script>";
?>

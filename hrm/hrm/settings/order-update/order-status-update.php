<?php
error_reporting(E_ALL); // Show all errors
ini_set('display_errors', 1);

session_start();
require_once('../../database.php');

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $tracking_no = $_POST['tracking_no'];
    $origin = $_POST['origin'];
    $destination = $_POST['destination'];
    $inscan_datetime = $_POST['inscan_datetime'];
    $inscan_status = $_POST['inscan_status'];
    $outscan_datetime = $_POST['outscan_datetime'];
    $outscan_status = $_POST['outscan_status'];
    $order_status = $_POST['order_status'];
    $remarks = $_POST['remarks'];
    $scan_location = $_POST['scan_location'];
    $delivery_associate = $_POST['delivery_associate'];
    $page_url = $_POST['page_url'];

    // Insert into inscan table
    $sql_inscan = "INSERT INTO inscan (tracking_no, origin, destination, inscan_datetime, status) 
                   VALUES ('$tracking_no', '$origin', '$destination', '$inscan_datetime', '$inscan_status')";
    if (!mysqli_query($dbConn, $sql_inscan)) {
        die("Error in inscan: " . mysqli_error($dbConn));
    }

    // Insert into outscan table
    $sql_outscan = "INSERT INTO outscan (tracking_no, origin, destination, outscan_datetime, status, remarks, scan_location, delivery_associate) 
                    VALUES ('$tracking_no', '$origin', '$destination', '$outscan_datetime', '$outscan_status', '$remarks', '$scan_location', '$delivery_associate')";
    if (!mysqli_query($dbConn, $sql_outscan)) {
        die("Error in outscan: " . mysqli_error($dbConn));
    }

    $check_az_orders = mysqli_query($dbConn, "SELECT order_id, tracking_no FROM az_orders WHERE tracking_no = '$tracking_no'");
    if (!$check_az_orders) {
        die("Error in az_orders check: " . mysqli_error($dbConn));
    }
    
    $az_orders_num = mysqli_num_rows($check_az_orders);
    if ($az_orders_num > 0) {
        while ($row_cao = mysqli_fetch_array($check_az_orders)) {
            $order_id = $row_cao['order_id'];
        }

        // Update az_orders table
        $update_az_status = "UPDATE az_orders SET order_status = '$order_status' WHERE tracking_no = '$tracking_no'";
        if (!mysqli_query($dbConn, $update_az_status)) {
            die("Error updating az_orders: " . mysqli_error($dbConn));
        }

        // Check order status ID
        $get_status_id = mysqli_query($dbConnZylo, "SELECT * FROM oc_order_status WHERE name='$order_status'");
        if (!$get_status_id) {
            die("Error in getting order status: " . mysqli_error($dbConnZylo));
        }

        $status_id = null;
        while ($row_gsi = mysqli_fetch_array($get_status_id)) {
            $status_id = $row_gsi['order_status_id'];
        }

        if ($status_id !== null) {
            $oc_status_update = "UPDATE oc_order SET order_status_id = '$status_id' WHERE order_id = '$order_id'";
            if (!mysqli_query($dbConnZylo, $oc_status_update)) {
                die("Error updating oc_order: " . mysqli_error($dbConnZylo));
            }
        } else {
            die("Error: No matching status_id found for '$order_status'");
        }
    }

    echo "<script>
            alert('Data saved successfully.');
            window.location = '".$page_url."';
          </script>";
}
?>
<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');
require_once('../../database-settings.php');
$con = conexion();	

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $employee_id = $_POST['employee_id'];
    $date = $_POST['date'];
    $status = $_POST['status'];

    // Check if attendance already exists for the given employee and date
    $sql_check = "SELECT id FROM hr_attendance WHERE employee_id = '$employee_id' AND date = '$date'";
    $result_check = mysqli_query($dbConn, $sql_check);

    if (mysqli_num_rows($result_check) > 0) {
        // If attendance exists, update the status
        $sql_update = "UPDATE hr_attendance SET status = '$status' WHERE employee_id = '$employee_id' AND date = '$date'";
        mysqli_query($dbConn, $sql_update);
    } else {
        // If attendance doesn't exist, insert new record
        $sql_insert = "INSERT INTO hr_attendance (employee_id, date, status) VALUES ('$employee_id', '$date', '$status')";
        mysqli_query($dbConn, $sql_insert);
    }
    
    echo "Attendance updated successfully.";
}
?>

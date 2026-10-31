<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

	if ($_SERVER['REQUEST_METHOD'] == 'POST') {
		$employee_id = $_POST['employee_id'];
		$start_date = $_POST['start_date'];
		$end_date = $_POST['end_date'];
		$reason = $_POST['reason'];
		$status = $_POST['status'];

		$sql = "INSERT INTO hr_leaves (employee_id, start_date, end_date, reason, status) VALUES ('$employee_id', '$start_date', '$end_date', '$reason', '$status')";
		if (mysqli_query($dbConn, $sql)) {
			echo "<script type=\"text/javascript\">
						alert(\"Leave request created successfully.\");
						//window.location = \"../../hr-leave-requests.php\"
					</script>";
		} else {
			echo "Error: " . $sql . "<br>" . mysqli_error($dbConn);
		}
	}
	
    
?>

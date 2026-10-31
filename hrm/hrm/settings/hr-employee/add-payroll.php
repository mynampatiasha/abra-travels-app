<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

	if ($_SERVER["REQUEST_METHOD"] == "POST") {
		// Get form data and sanitize
		$employee_id = mysqli_real_escape_string($dbConn, $_POST['employee_id']);
		$salary_amount = mysqli_real_escape_string($dbConn, $_POST['salary_amount']);
		$pay_date = mysqli_real_escape_string($dbConn, $_POST['pay_date']);
		$comment = mysqli_real_escape_string($dbConn, $_POST['comment']);
		
		// Insert query
		$sql = "INSERT INTO hr_payroll (employee_id, amount, pay_date, comment) 
				VALUES ('$employee_id', '$salary_amount', '$pay_date', '$comment')";
		
		// Execute the query
		if (mysqli_query($dbConn, $sql)) {
			echo "<script type=\"text/javascript\">
						alert(\"New payroll entry added successfully.\");
						window.location = \"../../hr-payroll.php\"
					</script>";
		} else {
			echo "Error: " . $sql . "<br>" . mysqli_error($dbConn);
		}

	}
    
?>

<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

	if ($_SERVER['REQUEST_METHOD'] == 'POST') {
		$name = $_POST['name'];
		$email = $_POST['email'];
		$phone = $_POST['phone'];
		$department = $_POST['department'];
		$hire_date = $_POST['hire_date'];
		$salary = $_POST['salary'];
		$status = $_POST['status'];

		$sql = "INSERT INTO hr_employees (name, email, phone, department, hire_date, salary, status) VALUES ('$name', '$email', '$phone', '$department', '$hire_date', '$salary', '$status')";
		if (mysqli_query($dbConn, $sql)) {
			echo "<script type=\"text/javascript\">
						alert(\"New employee created successfully.\");
						window.location = \"../../hr-employees-list.php\"
					</script>";
		} else {
			echo "Error: " . $sql . "<br>" . mysqli_error($dbConn);
		}
	}
	
    
?>

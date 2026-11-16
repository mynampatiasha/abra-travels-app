<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

	if ($_SERVER['REQUEST_METHOD'] == 'POST') {
		$name = $_POST['name'];

		$sql = "INSERT INTO hr_departments (name) VALUES ('$name')";
		if (mysqli_query($dbConn, $sql)) {
			echo "<script type=\"text/javascript\">
						alert(\"New department created successfully.\");
						window.location = \"../../hr-departments-list.php\"
					</script>";
		} else {
			echo "Error: " . $sql . "<br>" . mysqli_error($dbConn);
		}
	}
	
    
?>

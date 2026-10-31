<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

	if ($_SERVER['REQUEST_METHOD'] === 'POST') {
		// Get the selected month and year from the form
		$month = $_POST['month'];
		$year = $_POST['year'];
		
		// Create the date range for the selected month
		$start_date = "$year-$month-01";
		$end_date = date("Y-m-t", strtotime($start_date)); // Last date of the selected month

		// Fetch the employee attendance data
		$sql = "
			SELECT e.id, e.name, 
			SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_days,
			SUM(CASE WHEN a.status = 'absent' THEN 1 ELSE 0 END) AS absent_days
			FROM hr_employees e
			LEFT JOIN hr_attendance a ON e.id = a.employee_id AND a.date BETWEEN '$start_date' AND '$end_date'
			WHERE e.status = 'active'
			GROUP BY e.id, e.name
			ORDER BY e.id
		";

		$result = mysqli_query($dbConn, $sql);

		// Set headers to indicate that the response should be treated as a file download
		header("Content-Type: application/vnd.ms-excel");
		header("Content-Disposition: attachment; filename=Attendance_Report_$year-$month.xls");
		header("Pragma: no-cache");
		header("Expires: 0");

		// Start outputting the table as HTML that Excel can understand
		echo "<table border='1'>";
		echo "<tr><th>Employee ID</th><th>Employee Name</th><th>Present Days</th><th>Absent Days</th></tr>";

		// Loop through each employee's attendance data and output the rows
		while ($row = mysqli_fetch_assoc($result)) {
			echo "<tr>";
			echo "<td>" . $row['id'] . "</td>";
			echo "<td>" . $row['name'] . "</td>";
			echo "<td>" . $row['present_days'] . "</td>";
			echo "<td>" . $row['absent_days'] . "</td>";
			echo "</tr>";
		}

		echo "</table>";

		exit(); // End script execution after output
	}
	
    
?>

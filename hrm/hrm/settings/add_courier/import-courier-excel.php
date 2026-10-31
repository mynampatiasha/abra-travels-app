<?php
	// CSV IMPORT - Uses SAME tracking logic as website form to prevent duplicates
	error_reporting(E_ERROR | E_WARNING | E_PARSE);
	
	session_start();
	
	require_once('../../database.php');
	require_once('../../database-settings.php');
	require '../../requirelanguage.php';
	require_once('../../funciones.php');

	function logDebug($message) {
		@error_log(date('[Y-m-d H:i:s] ') . $message . PHP_EOL, 3, __DIR__ . '/csv_import_debug.log');
	}

	if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_FILES["csv_file"])) {
		logDebug("=== CSV Import Started ===");
		
		if ($_FILES["csv_file"]["error"] !== UPLOAD_ERR_OK) {
			die("Upload Error. Please try again.<br><a href='../../panel-customer/bulk-upload-shipments.php'>Go Back</a>");
		}

		$file_tmp = $_FILES["csv_file"]["tmp_name"];
		$file_ext = strtolower(pathinfo($_FILES["csv_file"]["name"], PATHINFO_EXTENSION));

		if ($file_ext !== 'csv') {
			die("Invalid file type. Only CSV files allowed.<br><a href='../../panel-customer/bulk-upload-shipments.php'>Go Back</a>");
		}

		$handle = fopen($file_tmp, "r");
		if (!$handle) {
			die("Failed to open CSV file.<br><a href='../../panel-customer/bulk-upload-shipments.php'>Go Back</a>");
		}

		if (!isset($dbConn) || !$dbConn) {
			die("Database connection failed.<br><a href='../../panel-customer/bulk-upload-shipments.php'>Go Back</a>");
		}

		mysqli_set_charset($dbConn, "utf8mb4");

		// Get user session
		$officename = '';
		$user = '';
		
		if (isset($_SESSION['user_name']) && !empty($_SESSION['user_name'])) {
			$officename = $_SESSION['user_name'];
		} elseif (isset($_SESSION['email']) && !empty($_SESSION['email'])) {
			$officename = $_SESSION['email'];
		} elseif (isset($_SESSION['username']) && !empty($_SESSION['username'])) {
			$officename = $_SESSION['username'];
		} else {
			fclose($handle);
			die("Please log in first.<br><a href='../../panel-customer/bulk-upload-shipments.php'>Go Back</a>");
		}
		
		$officename = mysqli_real_escape_string($dbConn, $officename);
		
		$sql_user_query = mysqli_query($dbConn, "SELECT name FROM tbl_clients WHERE email='$officename' LIMIT 1");
		if ($sql_user_query && $row_user = mysqli_fetch_array($sql_user_query)) {
			$user = $row_user['name'];
		} else {
			$user = $officename;
		}

		// Use local timezone (same as website form)
		if (isset($_SESSION['ge_timezone'])) {
			date_default_timezone_set($_SESSION['ge_timezone']);
		}
		$local_timestamp = date("Y-m-d H:i:s");

		// Get company prefix
		$qryEmpresa = mysqli_query($dbConn, "SELECT prefijo, cons_no FROM company LIMIT 1");
		if (!$qryEmpresa || !($row_company = mysqli_fetch_array($qryEmpresa))) {
			fclose($handle);
			die("Company configuration not found.<br><a href='../../panel-customer/bulk-upload-shipments.php'>Go Back</a>");
		}
		
		$pre = $row_company["prefijo"];
		$cons = $row_company["cons_no"];

		$row_num = 0;
		$errors = [];
		$success_count = 0;
		
		function cleanCsvData($value, $dbConn) {
			if ($value === null) return '';
			$value = str_replace("\xEF\xBB\xBF", '', $value);
			$value = str_replace(["\xA0", "\xC2\xA0"], ' ', $value);
			$value = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $value);
			$value = trim($value);
			if (!mb_check_encoding($value, 'UTF-8')) {
				$value = mb_convert_encoding($value, 'UTF-8', 'auto');
			}
			return mysqli_real_escape_string($dbConn, $value);
		}

		// ============================================================================
		// EXACT SAME TRACKING NUMBER LOGIC AS YOUR WEBSITE FORM (add-courier.php)
		// This ensures CSV imports and website forms NEVER conflict!
		// ============================================================================
		function generateTrackingNumber($dbConn, $pre, $cons) {
			// Get max from c_tracking table
			$pa = mysqli_query($dbConn, "SELECT MAX(cons_no) as maximo FROM c_tracking");
			$row_max = mysqli_fetch_array($pa);
			$max_from_tracking = $row_max['maximo'] ? intval($row_max['maximo']) : 0;

			// Get max number from courier table (catches website-created shipments)
			$safe_pre = mysqli_real_escape_string($dbConn, $pre);
			$pa2 = mysqli_query($dbConn, "SELECT MAX(CAST(REPLACE(tracking, '{$safe_pre}-', '') AS UNSIGNED)) as maximo FROM courier WHERE tracking LIKE '{$safe_pre}-%'");
			$row_max2 = mysqli_fetch_array($pa2);
			$max_from_courier = $row_max2['maximo'] ? intval($row_max2['maximo']) : 0;

			// Use whichever is highest + 1 (EXACT same logic as website)
			$cons_no = max($max_from_tracking, $max_from_courier, intval($cons)) + 1;
			
			$tracking_number = $pre . '-' . $cons_no;
			
			logDebug("Generated tracking: $tracking_number (cons_no: $cons_no, max_tracking: $max_from_tracking, max_courier: $max_from_courier)");
			
			return ['tracking' => $tracking_number, 'cons_no' => $cons_no];
		}
		// ============================================================================

		// Read CSV header
		$header = fgetcsv($handle, 10000, ",");
		if ($header === false) {
			fclose($handle);
			die("CSV file is empty.<br><a href='../../panel-customer/bulk-upload-shipments.php'>Go Back</a>");
		}

		// Process each row
		while (($data = fgetcsv($handle, 10000, ",")) !== FALSE) {
			$row_num++;

			if (count($data) < 26) {
				$errors[] = "Row $row_num: Expected 26 columns, found " . count($data) . ". Skipped.";
				continue;
			}

			$data = array_pad($data, 26, '');
			
			list($Shippername, $Shipperemail, $Shippercc, $Shipperphone, $Shipperaddress, 
				 $Pickuptime, $state, $ciudad, $zipcode, $altura, $ancho, $longitud, 
				 $totalpeso, $Qnty, $Shiptype, $shipping_method, $Comments,
				 $Receivername, $Receivercc_r, $Receiveraddress, $Receiveremail, 
				 $Receiverphone, $telefono1, $paisdestino, $state1, $city1, $zipcode1) = 
				array_map(function($value) use ($dbConn) {
					return cleanCsvData($value, $dbConn);
				}, $data);

			// Validate required fields
			if (empty($Shippername) || empty($Shipperphone) || empty($Shipperaddress) || 
				empty($Receivername) || empty($Receiverphone) || empty($Receiveraddress)) {
				$errors[] = "Row $row_num: Missing required fields. Skipped.";
				continue;
			}

			// Start transaction for this row (same as website form)
			mysqli_begin_transaction($dbConn);

			try {
				// Generate tracking number using SAME logic as website
				$tracking_data = generateTrackingNumber($dbConn, $pre, $cons);
				$tracking_number = $tracking_data['tracking'];
				$cons_no = $tracking_data['cons_no'];

				$status = 'Pending';
				
				// Get customer_id (same as website form)
				$customer_id = 0;
				$customer_query = mysqli_query($dbConn, "SELECT id FROM tbl_clients WHERE name = '$Shippername' OR email = '$Shipperemail' LIMIT 1");
				if($customer_row = mysqli_fetch_array($customer_query)) {
					$customer_id = (int)$customer_row['id'];
				}

				// Insert into courier table (SAME structure as website form)
				$sql_courier = "INSERT INTO courier (
					tracking, cons_no, letra, 
					ship_name, phone, s_add, cc, correo,
					rev_name, r_phone, telefono1, r_add, cc_r, email, 
					type, shipping_subtotal, altura, ancho, longitud, totalpeso, 
					qty, book_mode, mode, pick_date, schedule, pick_time, 
					state, ciudad, zipcode, paisdestino, state1, city1, zipcode1, 
					status, comments, officename, status_delivered, user, book_date, 
					pesoreal, dom_internation, shipping_method, customer_id
				) VALUES (
					'$tracking_number', '$cons_no', '$pre',
					'$Shippername', '$Shipperphone', '$Shipperaddress', '$Shippercc', '$Shipperemail',
					'$Receivername', '$Receiverphone', '$telefono1', '$Receiveraddress', '$Receivercc_r', '$Receiveremail',
					'$Shiptype', '0', '$altura', '$ancho', '$longitud', '$totalpeso',
					'$Qnty', '', '', '$local_timestamp', '', '$Pickuptime',
					'$state', '$ciudad', '$zipcode', '$paisdestino', '$state1', '$city1', '$zipcode1',
					'$status', '$Comments', '$officename', 0, '$user', '$local_timestamp',
					'', '', '$shipping_method', $customer_id
				)";
				
				if (!mysqli_query($dbConn, $sql_courier)) {
					throw new Exception("Error saving to courier table: " . mysqli_error($dbConn));
				}

				// Insert into c_tracking table (same as website form)
				$sql_tracking = "INSERT INTO c_tracking (tracking, cons_no, officename, user, book_date) 
								 VALUES ('$tracking_number', '$cons_no', '$officename', '$user', '$local_timestamp')";
				if (!mysqli_query($dbConn, $sql_tracking)) {
					throw new Exception("Error saving to c_tracking table: " . mysqli_error($dbConn));
				}

				// Insert into accounting table (same as website form)
				$sql_accounting = "INSERT INTO accounting (tracking, ship_name, book_mode, shipping_subtotal, office, user, book_date) 
								   VALUES ('$tracking_number', '$Shippername', '', '0', '$officename', '$user', '$local_timestamp')";
				if (!mysqli_query($dbConn, $sql_accounting)) {
					throw new Exception("Error saving to accounting table: " . mysqli_error($dbConn));
				}

				// Commit transaction
				mysqli_commit($dbConn);
				$success_count++;
				
				logDebug("Row $row_num: Success - $tracking_number");

			} catch (Exception $e) {
				mysqli_rollback($dbConn);
				$errors[] = "Row $row_num: " . $e->getMessage();
				logDebug("Row $row_num: Error - " . $e->getMessage());
				continue;
			}
		}

		fclose($handle);
		logDebug("Import completed. Success: $success_count, Errors: " . count($errors));

		// Display results
		if (!empty($errors)) {
			echo "<h3>Import Completed</h3>";
			echo "<p style='color:green;'><strong>Successfully imported: $success_count records</strong></p>";
			
			if (count($errors) > 0) {
				echo "<h4>Errors (" . count($errors) . "):</h4>";
				echo "<div style='max-height:300px; overflow-y:auto; border:1px solid #ccc; padding:10px; background:#fff;'>";
				echo "<ul style='color:red; margin:0;'>";
				foreach ($errors as $error) {
					echo "<li>" . htmlspecialchars($error) . "</li>";
				}
				echo "</ul></div>";
			}
			
			echo "<br><br><a href='../../panel-customer/bulk-upload-shipments.php' style='padding:10px 20px; background:#007bff; color:white; text-decoration:none; border-radius:5px; display:inline-block;'>Go Back to Upload Page</a>";
		} else {
			echo "<script type=\"text/javascript\">
					alert(\"Success! $success_count shipments imported with unique tracking numbers.\");
					window.location = \"../../panel-customer/bulk-upload-shipments.php\"
				</script>";
		}
	} else {
		echo "No file uploaded.<br><a href='../../panel-customer/bulk-upload-shipments.php'>Go Back</a>";
	}
?>
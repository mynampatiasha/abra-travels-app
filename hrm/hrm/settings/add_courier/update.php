<?php
	error_reporting(E_ERROR | E_WARNING | E_PARSE);
	session_start();
	require_once('../../database.php');
	require_once('../../database-settings.php');
	
	$cid = (int)$_POST['cid'];
	$Shippername = $_POST['Shippername'];
	$Shipperphone = $_POST['Shipperphone'];
	$Shipperaddress = $_POST['Shipperaddress'];
	$Shippercc = $_POST['Shippercc'];
	
	$Receivername = $_POST['Receivername'];
	$Receiverphone = $_POST['Receiverphone'];
	$Receiveraddress = $_POST['Receiveraddress'];
	$Receivercc_r = $_POST['Receivercc_r'];
	$Receiveremail = $_POST['Receiveremail'];
	
	$Shiptype = $_POST['Shiptype'];
	$Weight = $_POST['Weight'];
	$kiloadicional = $_POST['kiloadicional'];
	$variable = $_POST['variable'];
	$shipping_subtotal = $_POST['shipping_subtotal'];
	$Invoiceno = $_POST['Invoiceno'];
	$Qnty = $_POST['Qnty'];
	
	$altura = $_POST['altura'];
	$ancho = $_POST['ancho'];
	$longitud = $_POST['longitud'];
	$totalpeso = $_POST['totalpeso'];
	$pesoreal = $_POST['pesoreal'];
	
	$Bookingmode = $_POST['Bookingmode'];
	$Totalfreight = $_POST['Totalfreight'];
	$Totaldeclarate = $_POST['Totaldeclarate'];
	$Totaldeclarado = $_POST['Totaldeclarado'];
	$Mode = $_POST['Mode'];
	
	$Packupdate = $_POST['Packupdate'];
	$Schedule = $_POST['Schedule'];
	$Pickuptime = $_POST['Pickuptime'];
	$iso = $_POST['iso'];
	$state = $_POST['state'];
	$ciudad = $_POST['ciudad'];
	
	$paisdestino = $_POST['paisdestino'];
	$iso1 = $_POST['iso1'];
	$state1 = $_POST['state1'];
	$city1 = $_POST['city1'];
	$status = $_POST['status'];
	$dom_internation = $_POST['dom_internation'];  
	$Comments = $_POST['Comments'];
	$officename = $_POST['officename'];
	//$user = $_POST['user'];	
	$tracking = $_POST['tracking'];	
	$cons_no = $_POST['cons_no'];	
	$shipping_method = $_POST['shipping_method'];	
	
	$reference_no = $_POST['reference_no'];
    $delivery_aggregator = $_POST['delivery_aggregator'];
	
	// NEW: Warehouse Location Fields (Optional)
	$warehouse_country = isset($_POST['warehouse_country']) ? $_POST['warehouse_country'] : '';
	$warehouse_state = isset($_POST['warehouse_state']) ? $_POST['warehouse_state'] : '';
	$warehouse_city = isset($_POST['warehouse_city']) ? $_POST['warehouse_city'] : '';
	$warehouse_id = isset($_POST['warehouse_id']) && $_POST['warehouse_id'] !== '' ? (int)$_POST['warehouse_id'] : 'NULL';
	
	$tracking_no_check = mysqli_query($dbConn, "SELECT tracking FROM courier WHERE cid = '$cid'");
	while($row = mysqli_fetch_array($tracking_no_check)){
		$current_tracking_no = $row['tracking'];
	}
	
	if(empty($current_tracking_no)){
		$sql_1 = "INSERT INTO c_tracking (tracking,cons_no,officename, book_date)
				VALUES('$tracking','$cons_no','$officename',curdate() )";	
			//echo $sql;
		dbQuery($sql_1);
	}
	
	// Updated SQL with warehouse fields
	$sql = "UPDATE courier
   SET ship_name='$Shippername',
       tracking='$tracking',
       phone='$Shipperphone',
       s_add='$Shipperaddress', 
       cc='$Shippercc', 
       rev_name='$Receivername',
       r_phone='$Receiverphone',
       r_add='$Receiveraddress', 
       cc_r='$Receivercc_r', 
       email='$Receiveremail', 
       type='$Shiptype', 
       shipping_method='$shipping_method', 
       invice_no='$Invoiceno', 
       mode='$Mode', 
       pick_date='$Packupdate', 
       schedule='$Schedule',
       pick_time='$Pickuptime',
       state='$state',
       ciudad='$ciudad',
       paisdestino='$paisdestino',
       state1='$state1',
       city1='$city1',
       book_mode='$Bookingmode',
       qty='$Qnty', 
       shipping_subtotal='$shipping_subtotal', 
       altura='$altura', 
       ancho='$ancho', 
       longitud='$longitud', 
       totalpeso='$totalpeso', 
       status='$status',
       dom_internation='$dom_internation', 
       comments='$Comments', 
       officename='$officename', 
       pesoreal='$pesoreal',
       reference_no='$reference_no',
       delivery_aggregator='$delivery_aggregator',
       warehouse_country='$warehouse_country',
       warehouse_state='$warehouse_state',
       warehouse_city='$warehouse_city',
       warehouse_id=$warehouse_id
   WHERE cid = '$cid'";	
		//echo $sql;
	dbQuery($sql);	
	
    require '../../requirelanguage.php';
	
	// Check if came from delivery-pod page
	if (isset($_SESSION['return_to_delivered']) && !empty($_SESSION['return_to_delivered'])) {
		$returnUrl = $_SESSION['return_to_delivered'];
		unset($_SESSION['return_to_delivered']);
		
		echo "<script type=\"text/javascript\">
				alert(\"$updateexit\");
				window.location = \"$returnUrl\"
			</script>";
	} else {
		// Default redirect to index
		echo "<script type=\"text/javascript\">
				alert(\"$updateexit\");
				window.location = \"../../index.php\"
			</script>";
	}
	//echo $Ship;
    
?>
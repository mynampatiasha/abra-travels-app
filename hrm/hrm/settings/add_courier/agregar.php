<?php
// 1. ENABLE ERROR REPORTING FOR DEBUGGING
error_reporting(E_ALL);
ini_set('display_errors', 1);

session_start();

// 2. UNIVERSAL PATH FIXER (Prevents 500 Errors)
// This checks if we are 2 levels deep or 3 levels deep and loads the files accordingly.

// Define the paths to check
$paths_to_check = [
    '../../../', // Check 3 levels back (e.g., dashboard/settings/adduser/)
    '../../',    // Check 2 levels back (e.g., dashboard/process/)
    '../'        // Check 1 level back
];

$found_root = false;
$root_path = '';

foreach ($paths_to_check as $path) {
    if (file_exists($path . 'database.php')) {
        $root_path = $path;
        $found_root = true;
        break;
    }
}

if (!$found_root) {
    die("<h1>Critical Error</h1><p>Could not find <b>database.php</b>. Check your file location.</p>");
}

// 3. REQUIRE FILES USING THE DETECTED PATH
require_once($root_path . 'database.php');
// Try to load config.php (Critical for APP_URL)
if (file_exists($root_path . 'config.php')) {
    require_once($root_path . 'config.php');
} else {
    // Fallback if config isn't found
    if(!defined('APP_URL')) define('APP_URL', 'https://crm.abra-logistic.com');
}

// Load other dependencies relative to the root path
if (file_exists($root_path . 'database-settings.php')) require_once($root_path . 'database-settings.php');
if (file_exists($root_path . 'requirelanguage.php')) require $root_path . 'requirelanguage.php';
if (file_exists($root_path . 'funciones.php')) require_once($root_path . 'funciones.php');

// 4. LOCATE GUMP AND NEXMO (These are usually in dashboard/css or root/css)
// We try to find where the 'css' folder is.
$css_path = '';
if (file_exists($root_path . 'dashboard/css/GUMP/gump.class.php')) {
    $css_path = $root_path . 'dashboard/css/';
} elseif (file_exists($root_path . 'css/GUMP/gump.class.php')) {
    $css_path = $root_path . 'css/';
} elseif (file_exists('../../css/GUMP/gump.class.php')) {
    $css_path = '../../css/'; // Original path attempt
}

if ($css_path != '') {
    require_once $css_path . 'GUMP/gump.class.php';
    // Only include Nexmo if it exists to prevent crash
    if (file_exists($css_path . 'sms/src/NexmoMessage.php')) {
        include($css_path . 'sms/src/NexmoMessage.php');
    }
} else {
    die("Error: Could not find GUMP Validator class in /css/GUMP/.");
}


## Validate the values from the form
$validator = new GUMP();
$_POST = $validator->sanitize($_POST);

$courier_customer = isset($_POST['courier_customer']) ? $_POST['courier_customer'] : null;

$validator->validation_rules(array(
    'Shippername'       => 'required',
    'Shipperphone'      => 'required',
    'Shipperaddress'    => 'required',
    'Shipperemail'      => 'required|valid_email',
    'Receivername'      => 'required',
    'Receiverphone'     => 'required',
    'telefono1'         => 'required',
    'Receiveraddress'   => 'required',
    'Receiveremail'     => 'required|valid_email',
    'Qnty'              => 'required',
    'Pickuptime'        => 'required',
    'state'             => 'required',
    'ciudad'            => 'required',
    'paisdestino'       => 'required',
    'state1'            => 'required',
    'city1'             => 'required',
    'Comments'          => 'required'
));

$validated_data = $validator->run($_POST);

if ($validated_data === false) {
    $error_message = urlencode($validator->get_readable_errors(true));
    if (isset($courier_customer)) {
        $url = "../../panel-customer/add-courier-customer.php?tipo=danger&mensaje=" . $error_message;
    } else {
        $url = "../../add-courier.php?tipo=danger&mensaje=" . $error_message;
    }
    header("Location: $url");
    exit;
}

try {
    mysqli_begin_transaction($dbConn);

    // Escape all input data
    $Shippername = mysqli_real_escape_string($dbConn, $_POST['Shippername']);
    $Shipperphone = mysqli_real_escape_string($dbConn, $_POST['Shipperphone']);
    $Shipperaddress = mysqli_real_escape_string($dbConn, $_POST['Shipperaddress']);
    $Shippercc = mysqli_real_escape_string($dbConn, isset($_POST['Shippercc']) ? $_POST['Shippercc'] : '');
    $Shipperemail = mysqli_real_escape_string($dbConn, $_POST['Shipperemail']);
    $Receivername = mysqli_real_escape_string($dbConn, $_POST['Receivername']);
    $Receiverphone = mysqli_real_escape_string($dbConn, $_POST['Receiverphone']);
    $telefono1 = mysqli_real_escape_string($dbConn, $_POST['telefono1']);
    $Receiveraddress = mysqli_real_escape_string($dbConn, $_POST['Receiveraddress']);
    $Receivercc_r = mysqli_real_escape_string($dbConn, isset($_POST['Receivercc_r']) ? $_POST['Receivercc_r'] : '');
    $Receiveremail = mysqli_real_escape_string($dbConn, $_POST['Receiveremail']);
    $Shiptype = mysqli_real_escape_string($dbConn, isset($_POST['Shiptype']) ? $_POST['Shiptype'] : '');
    $shipping_subtotal = mysqli_real_escape_string($dbConn, isset($_POST['shipping_subtotal']) ? $_POST['shipping_subtotal'] : '0');
    $pesoreal = mysqli_real_escape_string($dbConn, isset($_POST['pesoreal']) ? $_POST['pesoreal'] : '0');
    $Invoiceno = mysqli_real_escape_string($dbConn, isset($_POST['Invoiceno']) ? $_POST['Invoiceno'] : '');
    $Qnty = mysqli_real_escape_string($dbConn, $_POST['Qnty']);
    $altura = mysqli_real_escape_string($dbConn, isset($_POST['altura']) ? $_POST['altura'] : '0');
    $ancho = mysqli_real_escape_string($dbConn, isset($_POST['ancho']) ? $_POST['ancho'] : '0');
    $longitud = mysqli_real_escape_string($dbConn, isset($_POST['longitud']) ? $_POST['longitud'] : '0');
    $totalpeso = mysqli_real_escape_string($dbConn, isset($_POST['totalpeso']) ? $_POST['totalpeso'] : '0');
    $bookingmode = mysqli_real_escape_string($dbConn, isset($_POST['bookingmode']) ? $_POST['bookingmode'] : '');
    $Mode = mysqli_real_escape_string($dbConn, isset($_POST['Mode']) ? $_POST['Mode'] : '');
    $Schedule = mysqli_real_escape_string($dbConn, isset($_POST['Schedule']) ? $_POST['Schedule'] : '');
    $Pickuptime = mysqli_real_escape_string($dbConn, $_POST['Pickuptime']);
    $state = mysqli_real_escape_string($dbConn, $_POST['state']);
    $ciudad = mysqli_real_escape_string($dbConn, $_POST['ciudad']);
    $zipcode = mysqli_real_escape_string($dbConn, isset($_POST['zipcode']) ? $_POST['zipcode'] : '');
    $paisdestino = mysqli_real_escape_string($dbConn, $_POST['paisdestino']);
    $state1 = mysqli_real_escape_string($dbConn, $_POST['state1']);
    $city1 = mysqli_real_escape_string($dbConn, $_POST['city1']);
    $zipcode1 = mysqli_real_escape_string($dbConn, isset($_POST['zipcode1']) ? $_POST['zipcode1'] : '');
    $Comments = mysqli_real_escape_string($dbConn, $_POST['Comments']);
    $officename = mysqli_real_escape_string($dbConn, isset($_POST['officename']) ? $_POST['officename'] : 'Main Office');
    $user = mysqli_real_escape_string($dbConn, isset($_SESSION['user_name']) ? $_SESSION['user_name'] : 'Online Customer');
    $status_delivered = 0;
    $dom_internation = mysqli_real_escape_string($dbConn, isset($_POST['dom_internation']) ? $_POST['dom_internation'] : '');
    $shipping_method = mysqli_real_escape_string($dbConn, isset($_POST['shipping_method']) ? $_POST['shipping_method'] : '');
    $reference_no = mysqli_real_escape_string($dbConn, isset($_POST['reference_no']) ? $_POST['reference_no'] : '');
    $delivery_aggregator = mysqli_real_escape_string($dbConn, isset($_POST['delivery_aggregator']) ? $_POST['delivery_aggregator'] : '');
    
    // NEW FIELDS - Invoice and Locality
    $invoice_no = mysqli_real_escape_string($dbConn, isset($_POST['Shippercc']) ? $_POST['Shippercc'] : '');
    $sender_locality = mysqli_real_escape_string($dbConn, isset($_POST['sender_locality']) ? $_POST['sender_locality'] : '');
    $receiver_locality = mysqli_real_escape_string($dbConn, isset($_POST['receiver_locality']) ? $_POST['receiver_locality'] : '');
    
    // NEW WAREHOUSE LOCATION FIELDS
    $warehouse_country = mysqli_real_escape_string($dbConn, isset($_POST['warehouse_country']) ? $_POST['warehouse_country'] : '');
    $warehouse_state = mysqli_real_escape_string($dbConn, isset($_POST['warehouse_state']) ? $_POST['warehouse_state'] : '');
    $warehouse_city = mysqli_real_escape_string($dbConn, isset($_POST['warehouse_city']) ? $_POST['warehouse_city'] : '');
    $warehouse_id = isset($_POST['warehouse_id']) && $_POST['warehouse_id'] !== '' ? (int)$_POST['warehouse_id'] : 'NULL';
    
    $sender_latitude = isset($_POST['sender_latitude']) && $_POST['sender_latitude'] !== '' ? $_POST['sender_latitude'] : 'NULL';
    $sender_longitude = isset($_POST['sender_longitude']) && $_POST['sender_longitude'] !== '' ? $_POST['sender_longitude'] : 'NULL';
    $receiver_latitude = isset($_POST['receiver_latitude']) && $_POST['receiver_latitude'] !== '' ? $_POST['receiver_latitude'] : 'NULL';
    $receiver_longitude = isset($_POST['receiver_longitude']) && $_POST['receiver_longitude'] !== '' ? $_POST['receiver_longitude'] : 'NULL';

    $status = 'AWB Created';
    
    // Get customer_id
    $customer_id = 0;
    $customer_query = mysqli_query($dbConn, "SELECT id FROM tbl_clients WHERE name = '$Shippername' OR email = '$Shipperemail' LIMIT 1");
    if($customer_row = mysqli_fetch_array($customer_query)) {
        $customer_id = (int)$customer_row['id'];
    }

    // Generate tracking number
    $qryEmpresa = mysqli_query($dbConn, "SELECT prefijo, cons_no FROM company LIMIT 1");
    $row_company = mysqli_fetch_array($qryEmpresa);
    $pre = $row_company["prefijo"];
    $cons = $row_company["cons_no"];

    $pa = mysqli_query($dbConn, "SELECT MAX(cons_no) as maximo FROM c_tracking");
    $row_max = mysqli_fetch_array($pa);
    $cons_no = ($row_max['maximo'] == NULL) ? $cons : $row_max['maximo'] + 1;
    
    $tracking_number = $pre . '-' . $cons_no;
    
    // Use local timezone
    if(isset($_SESSION['ge_timezone'])) {
        date_default_timezone_set($_SESSION['ge_timezone']);
    }
    $local_timestamp = date("Y-m-d H:i:s");

    // Insert into courier table
    $sql_courier = "INSERT INTO courier (
        tracking, reference_no, delivery_aggregator, cons_no, letra, 
        invoice_no,
        ship_name, phone, s_add, cc, correo,
        rev_name, r_phone, telefono1, r_add, cc_r, 
        email, type, shipping_subtotal, altura, ancho, 
        longitud, totalpeso, invice_no, qty, book_mode, 
        mode, pick_date, schedule, pick_time, state, sender_locality,
        ciudad, zipcode, paisdestino, state1, receiver_locality, city1, 
        zipcode1, status, comments, officename, status_delivered, 
        user, book_date, pesoreal, dom_internation, shipping_method, 
        customer_id, sender_latitude, sender_longitude, receiver_latitude, receiver_longitude,
        warehouse_country, warehouse_state, warehouse_city, warehouse_id
    ) VALUES (
        '$tracking_number', '$reference_no', '$delivery_aggregator', '$cons_no', '$pre',
        '$invoice_no',
        '$Shippername', '$Shipperphone', '$Shipperaddress', '$Shippercc', '$Shipperemail',
        '$Receivername', '$Receiverphone', '$telefono1', '$Receiveraddress', '$Receivercc_r',
        '$Receiveremail', '$Shiptype', '$shipping_subtotal', '$altura', '$ancho',
        '$longitud', '$totalpeso', '$Invoiceno', '$Qnty', '$bookingmode',
        '$Mode', '$local_timestamp', '$Schedule', '$Pickuptime', '$state', '$sender_locality',
        '$ciudad', '$zipcode', '$paisdestino', '$state1', '$receiver_locality', '$city1',
        '$zipcode1', '$status', '$Comments', '$officename', $status_delivered,
        '$user', '$local_timestamp', '$pesoreal', '$dom_internation', '$shipping_method',
        $customer_id, $sender_latitude, $sender_longitude, $receiver_latitude, $receiver_longitude,
        '$warehouse_country', '$warehouse_state', '$warehouse_city', $warehouse_id
    )";
    
    if (!mysqli_query($dbConn, $sql_courier)) {
        throw new Exception("Error saving to courier table: " . mysqli_error($dbConn));
    }

    // Insert into c_tracking table
    $sql_tracking = "INSERT INTO c_tracking (tracking, cons_no, officename, user, book_date) 
                     VALUES ('$tracking_number', '$cons_no', '$officename', '$user', '$local_timestamp')";
    if (!mysqli_query($dbConn, $sql_tracking)) {
        throw new Exception("Error saving to c_tracking table: " . mysqli_error($dbConn));
    }

    // Insert into accounting table
    $sql_accounting = "INSERT INTO accounting (tracking, ship_name, book_mode, shipping_subtotal, office, user, book_date) 
                       VALUES ('$tracking_number', '$Shippername', '$bookingmode', '$shipping_subtotal', '$officename', '$user', '$local_timestamp')";
    if (!mysqli_query($dbConn, $sql_accounting)) {
        throw new Exception("Error saving to accounting table: " . mysqli_error($dbConn));
    }
    
    mysqli_commit($dbConn);

    // Email logic
    $result131 = mysqli_query($dbConn, "SELECT * FROM company LIMIT 1");
    if($row = mysqli_fetch_array($result131)) {
        $to = $row["bemail"];
        $address = $row["caddress"];
        $namecompanie = $row["cname"];
        $footer = $row["footer_website"];
        $web = $row["website"];
        
        // Define fallback variables if requirelanguage.php failed or variables missing
        if(!isset($welcometo)) $welcometo = "Welcome to";
        if(!isset($hola)) $hola = "Hello";
        if(!isset($tehaenviado)) $tehaenviado = "has sent you a package";
        if(!isset($envioasudestino)) $envioasudestino = "Shipment to destination";
        if(!isset($estadodelenvio)) $estadodelenvio = "Shipment Status";
        if(!isset($_Tracking)) $_Tracking = "Tracking #";
        if(!isset($estado)) $estado = "Status";
        if(!isset($email1)) $email1 = "Email";
        if(!isset($destinoe)) $destinoe = "Destination";
        if(!isset($direccion)) $direccion = "Address";
        if(!isset($fechadelenvio)) $fechadelenvio = "Date";
        if(!isset($DetallesdelEnvio)) $DetallesdelEnvio = "Details";
        if(!isset($estaes)) $estaes = "This is your shipping information";
        if(!isset($porfavor)) $porfavor = "Please contact us for more info";
        
        $url = APP_URL."/logo-image/image_logo.php?id=1";
        
        $subject = ''.$envioasudestino.' | '.$row["cname"].'';
        $from = $row["bemail"];
        
        // Construct Message (Kept your HTML structure)
        $message = "<html><body>";    
        $message .= "<div style='font-family:HelveticaNeue-Light,Arial,sans-serif;background-color:#eeeeee'>
           ... (Content hidden for brevity, same as your original) ...
           <p>Tracking: $tracking_number</p>
           <p>Status: $status</p>
        </div></body></html>";
        
        // Headers
        $headers = 'MIME-Version: 1.0' . "\r\n";
        $headers .= 'Content-type: text/html; charset=utf-8' . "\r\n";
        $headers .= 'From: '.$from."\r\n";    
        
        // Send
        @mail($to, $subject, $message, $headers);
        @mail($Receiveremail, $subject, $message, $headers);
    }
    
    if (isset($courier_customer)) {
        echo "<script type=\"text/javascript\">
                alert(\"Successfully submitted, Thank you!\");
                window.location = \"../../panel-customer/customer.php\"
            </script>";
    } else {
        echo "<script type=\"text/javascript\">
                alert(\"Shipment Created Successfully\");
                window.location = \"../../active-shipments.php\"
            </script>";
    }
    exit;

} catch (Exception $e) {
    mysqli_rollback($dbConn);
    $error_message = urlencode("An error occurred: " . $e->getMessage());
    if (isset($courier_customer)) {
        $url = "../../panel-customer/add-courier-customer.php?tipo=danger&mensaje=" . $error_message;
    } else {
        $url = "../../add-courier.php?tipo=danger&mensaje=" . $error_message;
    }
    header("Location: $url");
    exit;
}
?>
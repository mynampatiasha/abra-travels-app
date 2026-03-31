<?php
// ============================================================================
// DATABASE CONNECTION FOR HRM FLEET MANAGEMENT
// ============================================================================
define('DB_HOST', 'localhost');
define('DB_USER', 'royaldxd_hrm_fleet_travels');
define('DB_PASS', 'Abragroup@123');  // ← YOUR PASSWORD HERE
define('DB_NAME', 'royaldxd_hrm_fleet');
global $dbConn;
function conexion() {
    global $dbConn;
    
    if (!isset($dbConn)) {
        $dbConn = mysqli_connect(DB_HOST, DB_USER, DB_PASS, DB_NAME);
        
        if (!$dbConn) {
            die("Connection failed: " . mysqli_connect_error());
        }
        
        mysqli_set_charset($dbConn, "utf8mb4");
    }
    
    return $dbConn;
}
$dbConn = conexion();
function dbQuery($sql) {
    global $dbConn;
    $result = mysqli_query($dbConn, $sql);
    if (!$result) {
        error_log("Query Error: " . mysqli_error($dbConn) . " | SQL: " . $sql);
    }
    return $result;
}
function dbFetchAssoc($result) {
    return mysqli_fetch_assoc($result);
}
function dbFetchArray($result) {
    return mysqli_fetch_array($result);
}
?>

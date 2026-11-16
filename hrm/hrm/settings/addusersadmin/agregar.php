<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

// Check connection
if (!$dbConn) {
    die("Connection failed: " . mysqli_connect_error());
}

$name_parson = $_POST['name_parson'];
$name = $_POST['name'];
$email = $_POST['email'];
$phone = $_POST['phone'];
$office = $_POST['office'];
$role = $_POST['role'];
$password = $_POST['pwd'];
$pwdmd5 = md5(PASS_SALT.$password);
$imagen = $_POST['imagen'];
$tipo_imagen = $_POST['tipo_imagen'];

// verificamos si esta marcado el check box activo
if (isset($_POST['estado']))
    $estado = $_POST['estado'];
else
    $estado = 0;

if (isset($_POST['type']))
    $type = $_POST['type'];
else
    $type = 0;

## Cargo la imagen por defecto
$tipo_imagen = "image/png";
$url = APP_URL."/img/user_image.png";

$imagen = imagecreatefromstring(file_get_contents($url));
imagealphablending($imagen, true);
imagesavealpha($imagen, true);

ob_start();
imagepng($imagen);
$string = ob_get_contents();
ob_end_clean();

// Query to check if the email or name already exists
$sql1 = mysqli_query($dbConn, "SELECT email, name FROM manager_admin WHERE email='$email' OR name='$name'");

if ($row = mysqli_fetch_array($sql1)) {
    echo "<script type=\"text/javascript\">
            alert(\"El email $email y nombre de usuario $name ya están registrados en la base de datos, por favor ingrese datos diferentes, gracias.\");
            window.location = \"../../add-new-users-admin.php\"
          </script>";
} else {
    $sql1 = "INSERT INTO manager_admin (name_parson, name, email, phone, office, role, pwd, estado, type, date, imagen, tipo_imagen)
             VALUES ('$name_parson', '$name', '$email', '$phone', '$office', '$role', '$pwdmd5', '$estado', '$type', CURDATE(), '".mysqli_real_escape_string($dbConn, $string)."', '$tipo_imagen')";
    
    mysqli_query($dbConn, $sql1);
}

echo "<script type=\"text/javascript\">
        alert(\"Thank you for your registration.\");
        window.location = \"../../add-new-users-admin.php\"
      </script>";

// Close connection
mysqli_close($dbConn);
?>

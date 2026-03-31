<?php
function isUser() {
    if (!isset($_SESSION['user_id'])) {
        header("Location: /login.php");
        exit;
    }
}

function aq($con, $sql) {
    return mysqli_query($con, $sql);
}
?>
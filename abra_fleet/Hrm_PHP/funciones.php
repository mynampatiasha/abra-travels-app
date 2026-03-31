<?php
function clean($data) {
    return htmlspecialchars(strip_tags(trim($data)));
}
?>
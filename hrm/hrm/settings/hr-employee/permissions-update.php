<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $user_id = $_POST['user_id'];
    $permissions = $_POST['permissions']; // Array of permissions with can_access and edit_delete

    // Delete existing permissions for the user
    $delete_query = "DELETE FROM manager_permissions WHERE user_id = $user_id";
    $dbConn->query($delete_query);

    // Insert updated permissions
    foreach ($permissions as $section => $values) {
        // Check values for `can_access` and `edit_delete` fields
        $can_access = isset($values['can_access']) ? 1 : 0;
        $edit_delete = isset($values['edit_delete']) ? 1 : 0;

        // Prepare and execute the query
        $insert_query = "INSERT INTO manager_permissions (user_id, section_name, can_access, edit_delete)
                         VALUES ('$user_id', '$section', '$can_access', '$edit_delete')";
        $dbConn->query($insert_query);
    }

    // Success/Error message
    if ($dbConn->error) {
        echo "Error: " . $dbConn->error;
    } else {
        echo "<script type=\"text/javascript\">
                  alert(\"Permissions updated successfully.\");
                  window.location = \"../../add-new-users.php\";
              </script>";
    }
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sign Up</title>
</head>
<body>
    <h2>Sign Up Form</h2>
    <form action="agregar.php" method="post">
        <label for="name_parson">Full Name:</label><br>
        <input type="text" id="name_parson" name="name_parson" required><br><br>
        
        <label for="name">Username:</label><br>
        <input type="text" id="name" name="name" required><br><br>
        
        <label for="email">Email:</label><br>
        <input type="email" id="email" name="email" required><br><br>
        
        <label for="phone">Phone:</label><br>
        <input type="text" id="phone" name="phone" required><br><br>
        
        <label for="office">Office:</label><br>
        <input type="text" id="office" name="office" required><br><br>
        
        <label for="role">Role:</label><br>
        <input type="text" id="role" name="role" required><br><br>
        
        <label for="pwd">Password:</label><br>
        <input type="password" id="pwd" name="pwd" required><br><br>
        
        <label for="estado">Active:</label>
        <input type="checkbox" id="estado" name="estado"><br><br>
        
        <label for="type">Type:</label>
        <input type="checkbox" id="type" name="type"><br><br>
        
        <button type="submit">Sign Up</button>
    </form>
</body>
</html>

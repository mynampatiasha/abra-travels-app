// controllers/userRoleController.js - User management for Abra Travel
const UserRole = require('../models/UserRole');

// Get all users
exports.getAllUsers = async (req, res) => {
  console.log('\n📋 GET ALL USERS');
  console.log('─'.repeat(80));
  
  try {
    const users = await UserRole.find().sort({ createdAt: -1 });
    console.log(`   Found ${users.length} users`);
    console.log('✅ USERS RETRIEVED');
    console.log('─'.repeat(80) + '\n');
    
    res.json(users);
  } catch (error) {
    console.error('❌ GET USERS FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ error: error.message });
  }
};

// Get user by ID
exports.getUserById = async (req, res) => {
  console.log('\n👤 GET USER BY ID');
  console.log('─'.repeat(80));
  console.log('   User ID:', req.params.id);
  
  try {
    const user = await UserRole.findById(req.params.id);
    if (!user) {
      console.log('   ❌ User not found');
      return res.status(404).json({ error: 'User not found' });
    }
    
    console.log('   ✅ User found:', user.email);
    console.log('─'.repeat(80) + '\n');
    res.json(user);
  } catch (error) {
    console.error('❌ GET USER FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ error: error.message });
  }
};

// Create new user
exports.createUser = async (req, res) => {
  console.log('\n📝 CREATE USER');
  console.log('─'.repeat(80));
  
  try {
    const { name, email, phone, password, role, customPermissions } = req.body;
    
    console.log('   Name:', name);
    console.log('   Email:', email);
    console.log('   Role:', role);
    console.log('   Password:', password ? '(provided)' : '(not provided)');
    console.log('   Custom Permissions:', customPermissions ? 'Yes' : 'No');

    // Validate required fields
    if (!name || !email || !password || !role) {
      console.log('   ❌ Missing required fields');
      return res.status(400).json({ 
        error: 'Name, email, password, and role are required' 
      });
    }

    // Check if user already exists
    const existingUser = await UserRole.findOne({ email });
    if (existingUser) {
      console.log('   ❌ User already exists');
      return res.status(400).json({ error: 'User with this email already exists' });
    }

    const user = new UserRole({
      name,
      email,
      phone,
      password, // Will be hashed by the pre-save hook
      role,
      customPermissions: customPermissions || null,
      status: 'active'
    });

    await user.save();
    
    console.log('   ✅ User created successfully');
    console.log('─'.repeat(80) + '\n');
    res.status(201).json(user);
  } catch (error) {
    console.error('❌ CREATE USER FAILED:', error.message);
    console.error('   Stack:', error.stack);
    console.error('─'.repeat(80) + '\n');
    res.status(400).json({ error: error.message });
  }
};

// Update user
exports.updateUser = async (req, res) => {
  console.log('\n✏️  UPDATE USER');
  console.log('─'.repeat(80));
  console.log('   User ID:', req.params.id);
  
  try {
    const { name, email, phone, password, role, customPermissions, status } = req.body;
    
    const user = await UserRole.findById(req.params.id);
    if (!user) {
      console.log('   ❌ User not found');
      return res.status(404).json({ error: 'User not found' });
    }

    // Check if email is being changed and if it's already taken
    if (email && email !== user.email) {
      const existingUser = await UserRole.findOne({ email });
      if (existingUser) {
        console.log('   ❌ Email already in use');
        return res.status(400).json({ error: 'Email already in use' });
      }
    }

    // Update fields
    if (name) user.name = name;
    if (email) user.email = email;
    if (phone !== undefined) user.phone = phone; // Allow empty string to clear phone
    if (password) user.password = password; // Will be hashed by pre-save hook
    if (role) user.role = role;
    if (status) user.status = status;
    
    // Handle custom permissions - can be updated or cleared
    if (customPermissions !== undefined) {
      user.customPermissions = customPermissions;
      console.log('   Custom permissions updated');
    }

    await user.save();
    
    console.log('   ✅ User updated successfully');
    console.log('─'.repeat(80) + '\n');
    res.json(user);
  } catch (error) {
    console.error('❌ UPDATE USER FAILED:', error.message);
    console.error('   Stack:', error.stack);
    console.error('─'.repeat(80) + '\n');
    res.status(400).json({ error: error.message });
  }
};

// Delete user
exports.deleteUser = async (req, res) => {
  console.log('\n🗑️  DELETE USER');
  console.log('─'.repeat(80));
  console.log('   User ID:', req.params.id);
  
  try {
    const user = await UserRole.findById(req.params.id);
    if (!user) {
      console.log('   ❌ User not found');
      return res.status(404).json({ error: 'User not found' });
    }

    await user.deleteOne();
    
    console.log('   ✅ User deleted successfully');
    console.log('─'.repeat(80) + '\n');
    res.json({ message: 'User deleted successfully' });
  } catch (error) {
    console.error('❌ DELETE USER FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ error: error.message });
  }
};

// Toggle user status
exports.toggleUserStatus = async (req, res) => {
  console.log('\n🔄 TOGGLE USER STATUS');
  console.log('─'.repeat(80));
  console.log('   User ID:', req.params.id);
  
  try {
    const user = await UserRole.findById(req.params.id);
    if (!user) {
      console.log('   ❌ User not found');
      return res.status(404).json({ error: 'User not found' });
    }

    user.status = user.status === 'active' ? 'inactive' : 'active';
    await user.save();
    
    console.log('   ✅ Status toggled to:', user.status);
    console.log('─'.repeat(80) + '\n');
    res.json(user);
  } catch (error) {
    console.error('❌ TOGGLE STATUS FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ error: error.message });
  }
};

// Search users
exports.searchUsers = async (req, res) => {
  console.log('\n🔍 SEARCH USERS');
  console.log('─'.repeat(80));
  
  try {
    const { q } = req.query;
    console.log('   Query:', q);
    
    if (!q) {
      return res.status(400).json({ error: 'Search query is required' });
    }
    
    const users = await UserRole.find({
      $or: [
        { name: { $regex: q, $options: 'i' } },
        { email: { $regex: q, $options: 'i' } }
      ]
    });

    console.log(`   Found ${users.length} users`);
    console.log('✅ SEARCH COMPLETE');
    console.log('─'.repeat(80) + '\n');
    res.json(users);
  } catch (error) {
    console.error('❌ SEARCH FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ error: error.message });
  }
};

// Login user (optional - if you need authentication)
exports.loginUser = async (req, res) => {
  console.log('\n🔐 USER LOGIN');
  console.log('─'.repeat(80));
  
  try {
    const { email, password } = req.body;
    console.log('   Email:', email);

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    // Find user by email
    const user = await UserRole.findOne({ email });
    if (!user) {
      console.log('   ❌ User not found');
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Check if user is active
    if (user.status !== 'active') {
      console.log('   ❌ User is inactive');
      return res.status(403).json({ error: 'Account is inactive' });
    }

    // Compare password
    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      console.log('   ❌ Invalid password');
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Update last active
    user.lastActive = Date.now();
    await user.save();

    console.log('   ✅ Login successful');
    console.log('─'.repeat(80) + '\n');
    
    // Return user data (password already excluded by toJSON method)
    res.json({
      message: 'Login successful',
      user
    });
  } catch (error) {
    console.error('❌ LOGIN FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ error: error.message });
  }
};
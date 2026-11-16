import re

with open('routes/admin-drivers.js', 'r', encoding='utf-8') as f:
    content = f.read()

pattern = r'\{\s*_id\s*:\s*new\s+ObjectId\(\s*driver\.assignedVehicle\s*\)\s*\}'
replacement = r'(/^[0-9a-fA-F]{24}$/.test(driver.assignedVehicle) ? { _id: new ObjectId(driver.assignedVehicle) } : { _id: null })'

new_content = re.sub(pattern, replacement, content)

with open('routes/admin-drivers.js', 'w', encoding='utf-8') as f:
    f.write(new_content)

print('Success')

import re

with open('routes/admin-drivers.js', 'r', encoding='utf-8') as f:
    content = f.read()

# Pattern for { _id: new ObjectId(req.params.id) }
# We replace it with: (/^[0-9a-fA-F]{24}$/.test(req.params.id) ? { _id: new ObjectId(req.params.id) } : { _id: null })
pattern = r'\{\s*_id\s*:\s*new\s+ObjectId\(\s*req\.params\.id\s*\)\s*\}'
replacement = r'(/^[0-9a-fA-F]{24}$/.test(req.params.id) ? { _id: new ObjectId(req.params.id) } : { _id: null })'

new_content = re.sub(pattern, replacement, content)

with open('routes/admin-drivers.js', 'w', encoding='utf-8') as f:
    f.write(new_content)

print('Success')

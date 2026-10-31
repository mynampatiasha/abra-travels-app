import re
import os

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Generic replace for mysqli_query(..., "INSERT INTO tickets (...) VALUES ('...', '...', '...', '...', 'Open', '', , NOW(), NOW(), ... )" )
    # Let's find all instances of mysqli_query that insert into tickets.
    
    # hr-leave-requests.php has this:
    # if(mysqli_query(, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at, leave_id, approver_level, deadline, timeline) VALUES ('','".addslashes(['name'])."','','','Open','',,NOW(),NOW(),,'primary',DATE_ADD(NOW(), INTERVAL 1 DAY),'1 day')")) {
    
    # We can write a specific replacement for hr-leave-requests.php since it has 3 of them repeated (primary, secondary, tertiary).
    
    def repl_leave(m):
        tn = m.group(1)
        name = m.group(2)
        sb = m.group(3)
        bd = m.group(4)
        prio = m.group(5)
        assign = m.group(6)
        app_level = m.group(7)
        return f"""(function() {{
             = json_encode([
                'subject'        => {sb},
                'message'        => {bd},
                'priority'       => {prio},
                'timeline'       => 24,
                'assigned_id'    => {assign},
                'creator_name'   => {name},
                'creator_email'  => 'system@abra-travels.com',
                'leave_id'       => ,
                'approver_level' => '{app_level}'
            ]);
             = curl_init('http://localhost:3001/api/tickets/internal/create');
            curl_setopt_array(, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_POST           => true,
                CURLOPT_POSTFIELDS     => ,
                CURLOPT_HTTPHEADER     => ['Content-Type: application/json', 'x-internal-key: abra_internal_2026'],
                CURLOPT_TIMEOUT        => 10,
            ]);
             = curl_exec();
             = curl_getinfo(, CURLINFO_HTTP_CODE);
            curl_close();
            return ( === 200 ||  === 201);
        }})()"""

    if "hr-leave-requests.php" in filepath:
        # mysqli_query(, "INSERT INTO tickets (... timeline) VALUES ('','".addslashes(['name'])."','','','Open','',,NOW(),NOW(),,'primary',DATE_ADD(NOW(), INTERVAL 1 DAY),'1 day')")
        pattern = r"""mysqli_query\(\,\s*"INSERT INTO tickets\s*\([^\)]+\)\s*VALUES\s*\('([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'Open',\s*'([^']+)',\s*([^,]+),\s*NOW\(\),\s*NOW\(\),\s*\,\s*'([^']+)',[^"]+"\s*\)"""
        
        count = 0
        def _repl(m):
            nonlocal count
            count += 1
            return repl_leave(m)
            
        content = re.sub(pattern, _repl, content)
        if count > 0:
            print(f"Updated {count} leave inserts in hr-leave-requests")

    if "hr_screening.php" in filepath:
        # mysqli_prepare(, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW(), ?, ?)")
        # This uses prepared statements! It's better to just replace the execute block.
        # Too complex to do via Regex. Let's just create a mock mysqli_query or abstract it.
        pass

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

process_file(r"D:\Fleet_Management\Fleet_Management\Fleet Management\hrm\hrm\hr-leave-requests.php")

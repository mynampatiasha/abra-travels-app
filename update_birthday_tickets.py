import re
import sys

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # hr-employees-list.php specific replacement
    if "hr-employees-list.php" in filepath:
        old_block = r"""\ = 'BDAY-' \. date\('Ymd'\) \. '-' \. \\['employee_id'\] \. '-' \. rand\(100, 999\);\s+\ = "\s+INSERT INTO tickets\s+\(ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at\)\s+VALUES\s+\('\', '\', '\', '\', '\', '\', '\{\\['id'\]\}', NOW\(\), NOW\(\)\)\s+";\s+if\(mysqli_query\(\, \\)\) \{"""
        
        new_block = """ = json_encode([
                        'subject'        => ,
                        'message'        => ,
                        'priority'       => ,
                        'timeline'       => 24,
                        'assigned_name'  => ['name'],
                        'assigned_email' => ['personal_email'] ?? ['email'] ?? '',
                        'creator_name'   => ,
                        'creator_email'  => 'system@abra-travels.com',
                    ]);

                     = curl_init('http://localhost:3001/api/tickets/internal/create');
                    curl_setopt_array(, [
                        CURLOPT_RETURNTRANSFER => true,
                        CURLOPT_POST           => true,
                        CURLOPT_POSTFIELDS     => ,
                        CURLOPT_HTTPHEADER     => [
                            'Content-Type: application/json',
                            'x-internal-key: abra_internal_2026',
                        ],
                        CURLOPT_TIMEOUT        => 10,
                    ]);
                     = curl_exec();
                     = curl_getinfo(, CURLINFO_HTTP_CODE);
                    curl_close();

                    if ( === 200 ||  === 201) {
                         = json_decode(, true);
                         = ['ticket']['ticketNumber'] ?? ['ticket']['ticket_number'] ?? ['ticket_number'] ?? ['ticketNumber'] ?? 'BDAY-API';"""
        
        content = re.sub(old_block, new_block, content, flags=re.MULTILINE)
        
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Updated hr-employees-list.php")
        return

process_file(r"D:\Fleet_Management\Fleet_Management\Fleet Management\hrm\hrm\hr-employees-list.php")

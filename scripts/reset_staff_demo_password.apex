User staff = [
    SELECT Id
    FROM User
    WHERE Username = 'hms.staff.00dg500000crbzeeat@example.com'
    LIMIT 1
];
System.setPassword(staff.Id, 'HmsStaff@2026');
System.debug('Reset staff demo password for ' + staff.Id);

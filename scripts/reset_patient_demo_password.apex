User patient = [
    SELECT Id
    FROM User
    WHERE Username = 'hms.patient.demo.00dg500000crbzeeat@example.com'
    LIMIT 1
];
System.setPassword(patient.Id, 'HmsPatient@2027');
System.debug('Reset patient demo password for ' + patient.Id);

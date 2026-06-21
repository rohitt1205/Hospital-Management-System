String username = 'hms.patient.' + UserInfo.getOrganizationId().toLowerCase() + '@example.com';
String accessibleEmail = 'raibhoomikakp@gmail.com';
String freshPassword = 'HmsPatient@2026';

User patientUser = [
    SELECT Id, Username, Email, IsActive
    FROM User
    WHERE Username = :username
    LIMIT 1
];

patientUser.Email = accessibleEmail;
patientUser.IsActive = true;
update patientUser;

System.setPassword(patientUser.Id, freshPassword);

System.debug('Patient username: ' + patientUser.Username);
System.debug('Patient email for verification code: ' + accessibleEmail);
System.debug('Patient fresh password: ' + freshPassword);

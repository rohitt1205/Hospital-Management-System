String suffix = UserInfo.getOrganizationId().toLowerCase();
String patientUsername = 'hms.patient.demo.' + suffix + '@example.com';
String patientEmail = 'raibhoomikakp@gmail.com';
String demoPassword = 'HmsPatient@2026';

Profile patientProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'Standard Platform User'
    LIMIT 1
];

User patientUser;
List<User> users = [
    SELECT Id, Username, Email, IsActive
    FROM User
    WHERE Username = :patientUsername
    LIMIT 1
];

if (users.isEmpty()) {
    patientUser = new User(
        Alias = 'hmpdmo',
        CommunityNickname = 'hmspatientdemo' + suffix.substring(0, 5),
        Email = patientEmail,
        EmailEncodingKey = 'UTF-8',
        FirstName = 'HMS',
        IsActive = true,
        LanguageLocaleKey = 'en_US',
        LastName = 'Patient Demo',
        LocaleSidKey = 'en_US',
        ProfileId = patientProfile.Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        Username = patientUsername,
        UserPreferencesLightningExperiencePreferred = true
    );
    insert patientUser;
} else {
    patientUser = users[0];
    patientUser.Email = patientEmail;
    patientUser.IsActive = true;
    update patientUser;
}

System.setPassword(patientUser.Id, demoPassword);

PermissionSet patientPermission = [
    SELECT Id
    FROM PermissionSet
    WHERE Name = 'HMS_Patient_User'
    LIMIT 1
];

List<PermissionSetAssignment> existingAssignments = [
    SELECT Id
    FROM PermissionSetAssignment
    WHERE AssigneeId = :patientUser.Id
    AND PermissionSetId = :patientPermission.Id
    LIMIT 1
];
if (existingAssignments.isEmpty()) {
    insert new PermissionSetAssignment(
        AssigneeId = patientUser.Id,
        PermissionSetId = patientPermission.Id
    );
}

System.debug('Reachable patient username: ' + patientUsername);
System.debug('Reachable patient email: ' + patientEmail);
System.debug('Reachable patient password: ' + demoPassword);

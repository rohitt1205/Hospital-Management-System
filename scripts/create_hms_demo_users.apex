String suffix = UserInfo.getOrganizationId().toLowerCase();
String staffUsername = 'hms.staff.' + suffix + '@example.com';
String patientUsername = 'hms.patient.' + suffix + '@example.com';
String demoPassword = 'HmsDemo@12345';

Profile minimumProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'Minimum Access - Salesforce'
    LIMIT 1
];

User staffUser;
List<User> staffUsers = [
    SELECT Id, Username, IsActive
    FROM User
    WHERE Username = :staffUsername
    LIMIT 1
];
if (staffUsers.isEmpty()) {
    staffUser = new User(
        Alias = 'hmsstf',
        CommunityNickname = 'hmsstaff' + suffix.substring(0, 6),
        Email = staffUsername,
        EmailEncodingKey = 'UTF-8',
        FirstName = 'HMS',
        IsActive = true,
        LanguageLocaleKey = 'en_US',
        LastName = 'Staff',
        LocaleSidKey = 'en_US',
        ProfileId = minimumProfile.Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        Username = staffUsername
    );
    insert staffUser;
} else {
    staffUser = staffUsers[0];
    if (!staffUser.IsActive) {
        staffUser.IsActive = true;
        update staffUser;
    }
}

User patientUser;
List<User> patientUsers = [
    SELECT Id, Username, IsActive
    FROM User
    WHERE Username = :patientUsername
    LIMIT 1
];
if (patientUsers.isEmpty()) {
    patientUser = new User(
        Alias = 'hmspat',
        CommunityNickname = 'hmspatient' + suffix.substring(0, 6),
        Email = patientUsername,
        EmailEncodingKey = 'UTF-8',
        FirstName = 'HMS',
        IsActive = true,
        LanguageLocaleKey = 'en_US',
        LastName = 'Patient',
        LocaleSidKey = 'en_US',
        ProfileId = minimumProfile.Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        Username = patientUsername
    );
    insert patientUser;
} else {
    patientUser = patientUsers[0];
    if (!patientUser.IsActive) {
        patientUser.IsActive = true;
        update patientUser;
    }
}

System.setPassword(staffUser.Id, demoPassword);
System.setPassword(patientUser.Id, demoPassword);

Map<String, PermissionSet> permissionSets = new Map<String, PermissionSet>();
for (PermissionSet ps : [
    SELECT Id, Name
    FROM PermissionSet
    WHERE Name IN ('HMS_Hospital_Staff', 'HMS_Patient_User')
]) {
    permissionSets.put(ps.Name, ps);
}

Set<String> existingAssignments = new Set<String>();
for (PermissionSetAssignment psa : [
    SELECT AssigneeId, PermissionSet.Name
    FROM PermissionSetAssignment
    WHERE AssigneeId IN :new Set<Id>{ staffUser.Id, patientUser.Id }
    AND PermissionSet.Name IN ('HMS_Hospital_Staff', 'HMS_Patient_User')
]) {
    existingAssignments.add(psa.AssigneeId + ':' + psa.PermissionSet.Name);
}

List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
if (!existingAssignments.contains(staffUser.Id + ':HMS_Hospital_Staff')) {
    assignments.add(new PermissionSetAssignment(
        AssigneeId = staffUser.Id,
        PermissionSetId = permissionSets.get('HMS_Hospital_Staff').Id
    ));
}
if (!existingAssignments.contains(patientUser.Id + ':HMS_Patient_User')) {
    assignments.add(new PermissionSetAssignment(
        AssigneeId = patientUser.Id,
        PermissionSetId = permissionSets.get('HMS_Patient_User').Id
    ));
}
if (!assignments.isEmpty()) {
    insert assignments;
}

System.debug('HMS staff username: ' + staffUsername);
System.debug('HMS patient username: ' + patientUsername);
System.debug('HMS demo password: ' + demoPassword);

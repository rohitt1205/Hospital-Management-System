String suffix = UserInfo.getOrganizationId().toLowerCase();
String staffUsername = 'hms.staff.' + suffix + '@example.com';
String patientUsername = 'hms.patient.' + suffix + '@example.com';

User staffUser = [
    SELECT Id, Username
    FROM User
    WHERE Username = :staffUsername
    LIMIT 1
];
User patientUser = [
    SELECT Id, Username
    FROM User
    WHERE Username = :patientUsername
    LIMIT 1
];

List<Staff__c> staffRecords = [
    SELECT Id, Salesforce_User__c
    FROM Staff__c
    ORDER BY CreatedDate
    LIMIT 1
];
if (!staffRecords.isEmpty()) {
    Staff__c staff = staffRecords[0];
    staff.Salesforce_User__c = staffUser.Id;
    update staff;
}

Patient__c patient = [
    SELECT Id, Portal_User__c, OwnerId
    FROM Patient__c
    ORDER BY CreatedDate
    LIMIT 1
];
patient.Portal_User__c = patientUser.Id;
patient.OwnerId = patientUser.Id;
update patient;

List<SObject> ownedPatientRecords = new List<SObject>();
for (Appointment__c row : [SELECT Id, OwnerId FROM Appointment__c WHERE Patient__c = :patient.Id]) {
    row.OwnerId = patientUser.Id;
    ownedPatientRecords.add(row);
}
for (Admission__c row : [SELECT Id, OwnerId FROM Admission__c WHERE Patient__c = :patient.Id]) {
    row.OwnerId = patientUser.Id;
    ownedPatientRecords.add(row);
}
for (Medical_Record__c row : [SELECT Id, OwnerId FROM Medical_Record__c WHERE Patient__c = :patient.Id]) {
    row.OwnerId = patientUser.Id;
    ownedPatientRecords.add(row);
}
for (Lab_Result__c row : [SELECT Id, OwnerId FROM Lab_Result__c WHERE Patient__c = :patient.Id]) {
    row.OwnerId = patientUser.Id;
    ownedPatientRecords.add(row);
}
for (Final_Report__c row : [SELECT Id, OwnerId FROM Final_Report__c WHERE Patient__c = :patient.Id]) {
    row.OwnerId = patientUser.Id;
    ownedPatientRecords.add(row);
}
for (Invoice__c row : [SELECT Id, OwnerId FROM Invoice__c WHERE Patient__c = :patient.Id]) {
    row.OwnerId = patientUser.Id;
    ownedPatientRecords.add(row);
}
for (Insurance_Policy__c row : [SELECT Id, OwnerId FROM Insurance_Policy__c WHERE Patient__c = :patient.Id]) {
    row.OwnerId = patientUser.Id;
    ownedPatientRecords.add(row);
}
if (!ownedPatientRecords.isEmpty()) {
    update ownedPatientRecords;
}

System.debug('Linked HMS staff user: ' + staffUsername);
System.debug('Linked HMS patient user: ' + patientUsername);

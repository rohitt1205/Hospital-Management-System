String suffix = UserInfo.getOrganizationId().toLowerCase();
String patientUsername = 'hms.patient.demo.' + suffix + '@example.com';

User patientUser = [
    SELECT Id, Username
    FROM User
    WHERE Username = :patientUsername
    LIMIT 1
];

Patient__c patient = [
    SELECT Id, Portal_User__c, OwnerId
    FROM Patient__c
    WHERE Name = 'Rahul Sharma'
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

System.debug('Linked Rahul Sharma to reachable patient user: ' + patientUsername);

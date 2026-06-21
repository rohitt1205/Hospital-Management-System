Admission__c admission = [
    SELECT Id, Name, Patient_Name__c, Phone__c, Patient__r.Name, Patient__r.Phone__c,
           Department__r.Name, Doctor_Assignment_Due__c
    FROM Admission__c
    WHERE Name = 'ADM-00050'
    LIMIT 1
];

String patientName = admission.Patient__r != null && String.isNotBlank(admission.Patient__r.Name)
    ? admission.Patient__r.Name
    : admission.Patient_Name__c;
String patientPhone = admission.Patient__r != null && String.isNotBlank(admission.Patient__r.Phone__c)
    ? admission.Patient__r.Phone__c
    : admission.Phone__c;

List<Task> tasks = [
    SELECT Id, Description
    FROM Task
    WHERE WhatId = :admission.Id
    AND Subject LIKE 'Emergency admission pending doctor assignment%'
    ORDER BY CreatedDate DESC
    LIMIT 10
];

for (Task taskRecord : tasks) {
    taskRecord.Description =
        'Emergency admission has breached the 15 minute doctor assignment SLA.' +
        '\nAdmission: ' + admission.Name +
        '\nPatient: ' + (String.isBlank(patientName) ? '-' : patientName) +
        '\nPhone: ' + (String.isBlank(patientPhone) ? '-' : patientPhone) +
        '\nDepartment: ' + (admission.Department__r == null ? '-' : admission.Department__r.Name) +
        '\nDue At: ' + String.valueOf(admission.Doctor_Assignment_Due__c);
}
update tasks;

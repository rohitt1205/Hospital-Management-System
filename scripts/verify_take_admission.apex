Savepoint sp = Database.setSavepoint();
try {
    Appointment__c appointment = [
        SELECT Id
        FROM Appointment__c
        WHERE Id NOT IN (SELECT Appointment__c FROM Admission__c WHERE Appointment__c != null)
        LIMIT 1
    ];

    Id admissionId = TakeAdmissionController.createAdmission(appointment.Id);
    Admission__c admission = [
        SELECT Id, Appointment__c, Patient__c, Admission_Type__c, Status__c
        FROM Admission__c
        WHERE Id = :admissionId
    ];

    System.assertEquals(appointment.Id, admission.Appointment__c);
    System.assertEquals('Planned', admission.Admission_Type__c);
    System.assertEquals('Draft', admission.Status__c);
    System.assertNotEquals(null, admission.Patient__c, 'Take Admission should produce an Admission linked to a Patient.');

    System.debug('HMS_TAKE_ADMISSION_OK admissionId=' + admissionId + ' patientId=' + admission.Patient__c);
} finally {
    Database.rollback(sp);
}

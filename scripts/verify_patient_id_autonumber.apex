Savepoint sp = Database.setSavepoint();
try {
    Patient__c patient = new Patient__c(
        Name = 'Patient ID Verification',
        Patient_Category__c = 'Normal',
        Status__c = 'Active'
    );
    insert patient;

    patient = [
        SELECT Patient_ID__c
        FROM Patient__c
        WHERE Id = :patient.Id
    ];

    System.assert(patient.Patient_ID__c != null && patient.Patient_ID__c.startsWith('p-'), 'Patient ID should be auto-generated with p- prefix.');
    System.debug('HMS_PATIENT_ID_OK ' + patient.Patient_ID__c);
} finally {
    Database.rollback(sp);
}

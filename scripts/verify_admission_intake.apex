Savepoint sp = Database.setSavepoint();
try {
    Admission__c admission = new Admission__c(
        Patient_Name__c = 'Verification Patient',
        Phone__c = '9876543210',
        Age__c = 42,
        Gender__c = 'Male',
        Weight_Kg__c = 72,
        Blood_Group__c = 'O+',
        Email__c = 'verify.patient@example.com',
        Aadhaar_Last_4__c = '1234',
        Address__c = 'Verification Address',
        Symptoms__c = 'Fever and chest discomfort',
        Admission_Type__c = 'Emergency',
        Admission_Date_Time__c = System.now(),
        Status__c = 'Admitted'
    );
    insert admission;

    admission = [
        SELECT Id, Name, Patient__c
        FROM Admission__c
        WHERE Id = :admission.Id
    ];
    System.assertNotEquals(null, admission.Patient__c, 'Admission should auto-link a created Patient.');

    Patient__c patient = [
        SELECT Name, Patient_ID__c, Phone__c, Email__c, Gender__c, Blood_Group__c,
               Aadhaar_Last_4__c, Address__c, Status__c
        FROM Patient__c
        WHERE Id = :admission.Patient__c
    ];
    System.assertEquals('Verification Patient', patient.Name);
    System.assert(patient.Patient_ID__c != null && patient.Patient_ID__c.startsWith('p-'), 'Patient ID should be auto-generated with p- prefix.');
    System.assertEquals('9876543210', patient.Phone__c);
    System.assertEquals('verify.patient@example.com', patient.Email__c);
    System.assertEquals('Male', patient.Gender__c);
    System.assertEquals('O+', patient.Blood_Group__c);
    System.assertEquals('1234', patient.Aadhaar_Last_4__c);
    System.assertEquals('Admitted', patient.Status__c);

    System.debug('HMS_VERIFY_OK admission=' + admission.Name + ' patient=' + patient.Name);
} finally {
    Database.rollback(sp);
}

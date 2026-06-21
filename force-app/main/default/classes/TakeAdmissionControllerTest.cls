@isTest
private class TakeAdmissionControllerTest {
    @isTest
    static void testCreateAdmission() {
        // Create Department
        Department__c dept = new Department__c(Name = 'Cardiology', Active__c = true, Is_Medical_Department__c = true);
        // If there's a lookup filter or status field, let's make sure it's valid.
        insert dept;

        // Create Doctor
        Doctor__c doc = new Doctor__c(
            Name = 'Dr. Test LWC', 
            Department__c = dept.Id
        );
        insert doc;

        // Create Patient
        Patient__c patient = new Patient__c(
            Name = 'Patient LWC Test',
            Status__c = 'Active'
        );
        insert patient;

        // Create Appointment
        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doc.Id,
            Department__c = dept.Id,
            Appointment_Date_Time__c = System.now().addHours(1),
            Appointment_Date__c = Date.today().addDays(1),
            Appointment_Time__c = '10:00',
            Status__c = 'Confirmed'
        );
        insert appointment;

        Test.startTest();
        // First creation
        Id admissionId = TakeAdmissionController.createAdmission(appointment.Id);
        System.assertNotEquals(null, admissionId, 'Admission Id should be returned.');

        // Second call (idempotent, should return same record)
        Id secondAdmissionId = TakeAdmissionController.createAdmission(appointment.Id);
        System.assertEquals(admissionId, secondAdmissionId, 'Should return the same admission.');
        Test.stopTest();

        // Verify record values
        Admission__c admission = [
            SELECT Id, Appointment__c, Doctor__c, Department__c, Status__c, Admission_Type__c
            FROM Admission__c
            WHERE Id = :admissionId
        ];
        System.assertEquals(appointment.Id, admission.Appointment__c);
        System.assertEquals(doc.Id, admission.Doctor__c);
        System.assertEquals(dept.Id, admission.Department__c);
        System.assertEquals('Draft', admission.Status__c);

        appointment = [SELECT Has_Admission__c FROM Appointment__c WHERE Id = :appointment.Id];
        System.assertEquals(true, appointment.Has_Admission__c, 'Appointment should be flagged as having an admission.');
    }
}
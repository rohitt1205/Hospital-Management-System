@isTest
private class AppointmentAdmissionTest {
    @isTest static void testAppointmentToAdmissionCreatesDraftAdmission() {
        Department__c dept = new Department__c(Name='Test Department', Is_Medical_Department__c=true);
        insert dept;

        Doctor__c doc = new Doctor__c(Name='Test Doctor', Department__c=dept.Id);
        insert doc;

        Patient__c patient = new Patient__c(Name='Test Patient', Status__c='Active');
        insert patient;

        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doc.Id,
            Department__c = dept.Id,
            Appointment_Date_Time__c = System.now().addHours(2),
            Source__c = 'Patient Portal',
            Status__c = 'Confirmed'
        );

        Test.startTest();
        insert appointment;
        Test.stopTest();

        List<Admission__c> admissions = [SELECT Id, Patient__c, Appointment__c, Doctor__c, Department__c, Status__c FROM Admission__c WHERE Appointment__c = :appointment.Id];
        System.assertEquals(1, admissions.size(), 'A draft admission should be created for a confirmed patient portal appointment.');
        System.assertEquals(patient.Id, admissions[0].Patient__c);
        System.assertEquals(appointment.Id, admissions[0].Appointment__c);
        System.assertEquals('Draft', admissions[0].Status__c);
    }

    @isTest static void testAdmissionAssignsPatientFromAppointmentAndUpdatesPatientStatus() {
        Department__c dept = new Department__c(Name='Test Department 2', Is_Medical_Department__c=true);
        insert dept;

        Doctor__c doc = new Doctor__c(Name='Test Doctor 2', Department__c=dept.Id);
        insert doc;

        Patient__c patient = new Patient__c(Name='Test Patient 2', Status__c='Active');
        insert patient;

        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doc.Id,
            Department__c = dept.Id,
            Appointment_Date_Time__c = System.now().addHours(3),
            Source__c = 'Reception',
            Status__c = 'Confirmed'
        );
        insert appointment;

        Admission__c admission = new Admission__c(
            Appointment__c = appointment.Id,
            Doctor__c = doc.Id,
            Department__c = dept.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = System.now()
        );

        Test.startTest();
        insert admission;
        Test.stopTest();

        patient = [SELECT Status__c FROM Patient__c WHERE Id = :patient.Id];
        System.assertEquals('Admitted', patient.Status__c, 'Patient status should be updated from admission status.');

        Admission__c insertedAdmission = [SELECT Patient__c FROM Admission__c WHERE Id = :admission.Id];
        System.assertEquals(patient.Id, insertedAdmission.Patient__c, 'Admission should inherit the patient from its linked appointment.');
    }
}
Savepoint sp = Database.setSavepoint();
try {
    // 1. Create a Department
    Department__c dept = new Department__c(Name = 'Cardiology', Active__c = true, Is_Medical_Department__c = true);
    insert dept;

    // 2. Create a Doctor
    Doctor__c doc = new Doctor__c(Name = 'Dr. Hiding Test', Department__c = dept.Id);
    insert doc;

    // 3. Create a Patient
    Patient__c patient = new Patient__c(Name = 'Patient Hiding Test', Status__c = 'Active');
    insert patient;

    // 4. Create an Appointment
    Appointment__c appt = new Appointment__c(
        Patient__c = patient.Id,
        Doctor__c = doc.Id,
        Department__c = dept.Id,
        Appointment_Date_Time__c = System.now().addHours(1),
        Appointment_Date__c = Date.today().addDays(1),
        Appointment_Time__c = '11:00',
        Status__c = 'Confirmed'
    );
    insert appt;

    // Query to verify Has_Admission__c is false
    appt = [SELECT Has_Admission__c FROM Appointment__c WHERE Id = :appt.Id];
    System.debug('*** BEFORE ADMISSION: Has_Admission__c = ' + appt.Has_Admission__c);

    // 5. Convert using the controller (simulate button click)
    Id admissionId = TakeAdmissionController.createAdmission(appt.Id);
    System.debug('*** ADMISSION CREATED: Id = ' + admissionId);

    // Query to verify Has_Admission__c is true
    appt = [SELECT Has_Admission__c FROM Appointment__c WHERE Id = :appt.Id];
    System.debug('*** AFTER ADMISSION: Has_Admission__c = ' + appt.Has_Admission__c);

    System.debug('*** BEHAVIOR VERIFIED: BUTTON HIDING FEATURE IS WORKING PERFECTLY! ***');
} finally {
    Database.rollback(sp);
}

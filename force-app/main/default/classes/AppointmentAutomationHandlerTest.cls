@IsTest
private class AppointmentAutomationHandlerTest {

    @IsTest
    static void testBeforeSaveSkipsSchedulingOnStatusOnlyUpdate() {
        Department__c department = new Department__c(
            Name = 'Automation Dept',
            Is_Medical_Department__c = true
        );
        insert department;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr Automation',
            Department__c = department.Id,
            Availability_Status__c = 'Available',
            Active__c = true
        );
        insert doctor;

        Patient__c patient = new Patient__c(
            Name = 'Automation Patient',
            Status__c = 'Active',
            Email__c = 'automation.patient@example.com',
            Phone__c = '9000000001'
        );
        insert patient;

        Date futureDate = Date.today().addDays(4);
        Datetime futureDateTime = Datetime.newInstance(Date.today().addDays(2), Time.newInstance(9, 0, 0, 0));

        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date__c = futureDate,
            Appointment_Date_Time__c = futureDateTime,
            Appointment_Time__c = '09:00',
            Appointment_Type__c = 'OPD',
            Status__c = 'Requested',
            Source__c = 'Reception'
        );
        insert appt;

        appt.Status__c = 'Confirmed';
        Test.startTest();
        update appt;
        Test.stopTest();

        Appointment__c refreshed = [
            SELECT Status__c, Appointment_Date__c, Appointment_Date_Time__c, Appointment_Time__c
            FROM Appointment__c
            WHERE Id = :appt.Id
        ];
        System.assertEquals('Confirmed', refreshed.Status__c);
        System.assertEquals(futureDate, refreshed.Appointment_Date__c);
        System.assertEquals(futureDateTime, refreshed.Appointment_Date_Time__c);
        System.assertEquals('09:00', refreshed.Appointment_Time__c);
    }

    @IsTest
    static void testBeforeSaveDerivesDateWhenDateTimeChanges() {
        Department__c department = new Department__c(
            Name = 'Automation Dept 2',
            Is_Medical_Department__c = true
        );
        insert department;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr Automation 2',
            Department__c = department.Id,
            Availability_Status__c = 'Available',
            Active__c = true
        );
        insert doctor;

        Patient__c patient = new Patient__c(
            Name = 'Automation Patient 2',
            Status__c = 'Active',
            Email__c = 'automation.patient2@example.com',
            Phone__c = '9000000002'
        );
        insert patient;

        Date targetDate = Date.today().addDays(3);
        Datetime targetDateTime = Datetime.newInstance(targetDate, Time.newInstance(10, 15, 0, 0));

        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date__c = Date.today().addDays(1),
            Appointment_Date_Time__c = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(9, 0, 0, 0)),
            Appointment_Time__c = '09:00',
            Appointment_Type__c = 'OPD',
            Status__c = 'Requested',
            Source__c = 'Reception'
        );
        insert appt;

        appt.Appointment_Date_Time__c = targetDateTime;
        Test.startTest();
        update appt;
        Test.stopTest();

        Appointment__c refreshed = [
            SELECT Appointment_Date__c, Appointment_Time__c
            FROM Appointment__c
            WHERE Id = :appt.Id
        ];
        System.assertEquals(targetDate, refreshed.Appointment_Date__c);
        System.assertEquals('10:00', refreshed.Appointment_Time__c);
    }

    @IsTest
    static void testBeforeSaveBuildsDateTimeFromDateAndTimeOnInsert() {
        Department__c department = new Department__c(
            Name = 'Automation Dept 3',
            Is_Medical_Department__c = true
        );
        insert department;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr Automation 3',
            Department__c = department.Id,
            Availability_Status__c = 'Available',
            Active__c = true
        );
        insert doctor;

        Patient__c patient = new Patient__c(
            Name = 'Automation Patient 3',
            Status__c = 'Active',
            Email__c = 'automation.patient3@example.com',
            Phone__c = '9000000003'
        );
        insert patient;

        Date targetDate = Date.today().addDays(6);
        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date__c = targetDate,
            Appointment_Time__c = '11:00',
            Appointment_Type__c = 'OPD',
            Status__c = 'Requested',
            Source__c = 'Reception'
        );

        Test.startTest();
        insert appt;
        Test.stopTest();

        Appointment__c refreshed = [
            SELECT Appointment_Date_Time__c, Department__c
            FROM Appointment__c
            WHERE Id = :appt.Id
        ];
        System.assertNotEquals(null, refreshed.Appointment_Date_Time__c);
        System.assertEquals(department.Id, refreshed.Department__c);
    }
}
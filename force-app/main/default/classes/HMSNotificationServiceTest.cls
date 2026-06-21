@IsTest
private class HMSNotificationServiceTest {

    private static Department__c createDepartment(String name) {
        Department__c department = new Department__c(
            Name = name,
            Is_Medical_Department__c = true
        );
        insert department;
        return department;
    }

    private static Doctor__c createDoctor(String name, Id departmentId, String email) {
        Doctor__c doctor = new Doctor__c(
            Name = name,
            Department__c = departmentId,
            Active__c = true,
            Availability_Status__c = 'Available'
        );
        if (email != null) {
            doctor.Email__c = email;
        }
        insert doctor;
        return doctor;
    }

    private static Patient__c createPatient(String name) {
        Patient__c patient = new Patient__c(
            Name = name,
            Status__c = 'Active',
            Phone__c = '9000000001'
        );
        insert patient;
        return patient;
    }

    @IsTest
    static void testDoctorEmailAssignedOnInsert() {
        DoctorEmailAssignmentService.testRandomIndex = 0;
        Department__c department = createDepartment('Email Dept');

        Test.startTest();
        Doctor__c doctor = createDoctor('Dr Email Test', department.Id, null);
        Test.stopTest();

        doctor = [SELECT Email__c FROM Doctor__c WHERE Id = :doctor.Id];
        System.assertEquals(
            DoctorEmailAssignmentService.DOCTOR_EMAIL_POOL[0],
            doctor.Email__c,
            'New doctors should receive a random email from the org pool.'
        );
    }

    @IsTest
    static void testDoctorEmailBackfillBatch() {
        DoctorEmailAssignmentService.testRandomIndex = 1;
        Department__c department = createDepartment('Backfill Dept');
        Doctor__c doctor = createDoctor('Dr Backfill', department.Id, null);
        doctor.Email__c = null;
        update doctor;

        Test.startTest();
        Database.executeBatch(new DoctorEmailBackfillBatch(), 200);
        Test.stopTest();

        doctor = [SELECT Email__c FROM Doctor__c WHERE Id = :doctor.Id];
        System.assertEquals(
            DoctorEmailAssignmentService.DOCTOR_EMAIL_POOL[1],
            doctor.Email__c,
            'Backfill batch should populate blank doctor emails.'
        );
    }

    private static void assertEmailSent(String message) {
        System.assert(HMSNotificationService.testEmailsSentCount > 0, message);
    }

    @IsTest
    static void testDoctorEmailOnAppointmentCreate() {
        Department__c department = createDepartment('Appt Notify Dept');
        Doctor__c doctor = createDoctor('Dr Appt Notify', department.Id, 'prasantnov9@gmail.com');
        Patient__c patient = createPatient('Appt Patient');

        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date_Time__c = System.now().addDays(1),
            Appointment_Date__c = Date.today().addDays(1),
            Appointment_Time__c = '10:00',
            Status__c = 'Requested',
            Source__c = 'Reception'
        );
        insert appointment;

        Test.startTest();
        HMSNotificationService.sendDoctorAppointmentEmails(new Set<Id>{ appointment.Id });
        Test.stopTest();

        assertEmailSent('Doctor should receive an email when an appointment notification is sent.');
    }

    @IsTest
    static void testDoctorEmailOnAdmissionCreate() {
        Department__c department = createDepartment('Adm Notify Dept');
        Doctor__c doctor = createDoctor('Dr Adm Notify', department.Id, 'joshiprashant.0911@gmail.com');
        Patient__c patient = createPatient('Adm Patient');

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Status__c = 'Draft',
            Admission_Date_Time__c = System.now()
        );
        insert admission;

        Test.startTest();
        HMSNotificationService.sendDoctorAdmissionEmails(new Set<Id>{ admission.Id });
        Test.stopTest();

        assertEmailSent('Doctor should receive an email when an admission notification is sent.');
    }

    @IsTest
    static void testWardManagerEmailOnBedAllocation() {
        Department__c department = createDepartment('Bed Notify Dept');
        Doctor__c doctor = createDoctor('Dr Bed Notify', department.Id, 'doctor.bed@test.com');
        Patient__c patient = createPatient('Bed Patient');

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = System.now()
        );
        insert admission;

        Bed_Allocation__c allocation = new Bed_Allocation__c(
            Admission__c = admission.Id,
            Patient__c = patient.Id,
            Bed_Number__c = '1',
            Start_Date_Time__c = System.now(),
            Status__c = 'Occupied'
        );
        insert allocation;

        Test.startTest();
        HMSNotificationService.sendWardManagerBedEmails(new Set<Id>{ allocation.Id });
        Test.stopTest();

        assertEmailSent('Ward manager should receive an email when a bed allocation notification is sent.');
    }

    @IsTest
    static void testQueueableDispatchesAppointmentEmail() {
        Department__c department = createDepartment('Queue Appt Dept');
        Doctor__c doctor = createDoctor('Dr Queue Appt', department.Id, 'prasantnov9@gmail.com');
        Patient__c patient = createPatient('Queue Appt Patient');
        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date_Time__c = System.now().addDays(1),
            Appointment_Date__c = Date.today().addDays(1),
            Appointment_Time__c = '11:00',
            Status__c = 'Requested',
            Source__c = 'Reception'
        );
        insert appointment;

        Test.startTest();
        System.enqueueJob(new HMSNotificationQueueable(
            HMSNotificationQueueable.NotificationType.DOCTOR_APPOINTMENT,
            new List<Id>{ appointment.Id }
        ));
        Test.stopTest();

        assertEmailSent('Queueable should dispatch doctor appointment email.');
    }

    @IsTest
    static void testAppointmentHandlerAfterInsert() {
        Department__c department = createDepartment('Handler Direct Dept');
        Doctor__c doctor = createDoctor('Dr Handler Direct', department.Id, 'prasantnov9@gmail.com');
        Patient__c patient = createPatient('Handler Direct Patient');
        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date_Time__c = System.now().addDays(1),
            Status__c = 'Requested',
            Source__c = 'Reception'
        );
        insert appointment;

        Test.startTest();
        AppointmentAdmissionHandler.handleAfterInsert(new List<Appointment__c>{ appointment });
        Test.stopTest();

        assertEmailSent('Handler after insert should enqueue doctor notification email.');
    }

    @IsTest
    static void testDirectSendSkipsMissingDoctorEmail() {
        Department__c department = createDepartment('Missing Email Dept');
        Doctor__c doctor = createDoctor('Dr No Email', department.Id, null);
        doctor.Email__c = null;
        update doctor;
        Patient__c patient = createPatient('Missing Email Patient');

        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date_Time__c = System.now().addDays(1),
            Status__c = 'Requested',
            Source__c = 'Reception'
        );
        insert appointment;

        Integer emailsBefore = HMSNotificationService.testEmailsSentCount;
        HMSNotificationService.sendDoctorAppointmentEmails(new Set<Id>{ appointment.Id });
        System.assertEquals(
            emailsBefore,
            HMSNotificationService.testEmailsSentCount,
            'No email should be sent when the doctor has no email address.'
        );
    }

    @IsTest
    static void testBuildDoctorAppointmentEmailUsesDoctorRecord() {
        Department__c department = createDepartment('Build Appt Dept');
        Doctor__c doctor = createDoctor('Dr Build Appt', department.Id, 'prasantnov9@gmail.com');
        Patient__c patient = createPatient('Build Appt Patient');
        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date__c = Date.today().addDays(3),
            Appointment_Time__c = '14:30',
            Status__c = 'Requested',
            Source__c = 'Reception'
        );
        insert appointment;

        appointment = [
            SELECT Id, Name, Status__c, Appointment_Date__c, Appointment_Time__c,
                   Appointment_Date_Time__c, Patient__r.Name, Department__r.Name
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        doctor = [SELECT Id, Name, Email__c FROM Doctor__c WHERE Id = :doctor.Id];

        Messaging.SingleEmailMessage mail = HMSNotificationService.buildDoctorAppointmentEmail(
            appointment,
            doctor
        );
        System.assertNotEquals(null, mail, 'Appointment email should be built when doctor has email.');
        System.assertEquals(
            'prasantnov9@gmail.com',
            mail.getToAddresses()[0],
            'Appointment email should go to the doctor email address.'
        );
    }

    @IsTest
    static void testAdmissionHandlerNotifiesDoctor() {
        Department__c department = createDepartment('Handler Adm Dept');
        Doctor__c doctor = createDoctor('Dr Handler Adm', department.Id, 'joshiprashant.0911@gmail.com');
        Patient__c patient = createPatient('Handler Adm Patient');
        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Status__c = 'Draft',
            Admission_Date_Time__c = System.now()
        );
        insert admission;

        Integer emailsBefore = HMSNotificationService.testEmailsSentCount;
        Test.startTest();
        PatientAdmissionHandler.handleAfterInsert(new List<Admission__c>{ admission });
        Test.stopTest();

        System.assert(
            HMSNotificationService.testEmailsSentCount > emailsBefore,
            'Admission handler should notify the assigned doctor.'
        );
    }

    @IsTest
    static void testAdmissionStatusChangeNotifiesDoctor() {
        Department__c department = createDepartment('Adm Status Dept');
        Doctor__c doctor = createDoctor('Dr Adm Status', department.Id, 'prasantnov9@gmail.com');
        Patient__c patient = createPatient('Adm Status Patient');
        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Status__c = 'Draft',
            Admission_Date_Time__c = System.now()
        );
        insert admission;

        admission.Status__c = 'Admitted';
        update admission;

        Integer emailsBefore = HMSNotificationService.testEmailsSentCount;
        Test.startTest();
        PatientAdmissionHandler.handleAfterUpdate(
            new List<Admission__c>{ admission },
            new Map<Id, Admission__c>{ admission.Id => new Admission__c(Id = admission.Id, Status__c = 'Draft') }
        );
        Test.stopTest();

        System.assert(
            HMSNotificationService.testEmailsSentCount > emailsBefore,
            'Admission status change to Admitted should notify the doctor.'
        );
    }

    @IsTest
    static void testApplyLifecycleBeforeSaveSetsDischargeDate() {
        Department__c department = createDepartment('Lifecycle Dept');
        Doctor__c doctor = createDoctor('Dr Lifecycle', department.Id, 'prasantnov9@gmail.com');
        Patient__c patient = createPatient('Lifecycle Patient');
        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = System.now()
        );
        insert admission;

        admission.Status__c = 'Discharged';
        PatientAdmissionHandler.applyLifecycleBeforeSave(
            new List<Admission__c>{ admission },
            new Map<Id, Admission__c>{ admission.Id => new Admission__c(Id = admission.Id, Status__c = 'Admitted') }
        );

        System.assertNotEquals(
            null,
            admission.Actual_Discharge_Date_Time__c,
            'Discharge date should be set when status changes to Discharged.'
        );
    }

    @IsTest
    static void testEnqueueWardManagerBedNotificationsFromChange() {
        Department__c department = createDepartment('Bed Change Dept');
        Doctor__c doctor = createDoctor('Dr Bed Change', department.Id, 'prasantnov9@gmail.com');
        Patient__c patient = createPatient('Bed Change Patient');
        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = System.now()
        );
        insert admission;

        Bed_Allocation__c allocation = new Bed_Allocation__c(
            Admission__c = admission.Id,
            Patient__c = patient.Id,
            Bed_Number__c = '3',
            Start_Date_Time__c = System.now(),
            Status__c = 'Occupied'
        );
        insert allocation;

        Integer emailsBefore = HMSNotificationService.testEmailsSentCount;
        Test.startTest();
        HMSNotificationService.enqueueWardManagerBedNotificationsFromChange(
            new List<Bed_Allocation__c>{ allocation },
            new Map<Id, Bed_Allocation__c>()
        );
        Test.stopTest();

        System.assert(
            HMSNotificationService.testEmailsSentCount > emailsBefore,
            'Bed allocation change should enqueue ward manager notification.'
        );
    }

    @IsTest
    static void testAdmissionBedAssignmentNotifiesWardManager() {
        Department__c department = createDepartment('Adm Bed Ward Dept');
        Doctor__c doctor = createDoctor('Dr Adm Bed Ward', department.Id, 'prasantnov9@gmail.com');
        Patient__c patient = createPatient('Adm Bed Ward Patient');
        Ward__c ward = new Ward__c(
            Department__c = department.Id,
            Capacity__c = 10,
            Current_Occupancy__c = 0
        );
        insert ward;
        Room__c room = new Room__c(
            Name = 'Adm Bed Room',
            Ward__c = ward.Id,
            Room_Type__c = 'private ac room with extra bed'
        );
        insert room;
        Bed__c bed = new Bed__c(
            Name = 'Adm Bed 1',
            Room__c = room.Id,
            Bed_Type__c = 'Normal',
            Status__c = 'Available'
        );
        insert bed;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Ward__c = ward.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = System.now()
        );
        insert admission;

        Admission__c updatedAdmission = new Admission__c(
            Id = admission.Id,
            Bed__c = bed.Id,
            Ward__c = ward.Id,
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = admission.Admission_Date_Time__c
        );

        Integer emailsBefore = HMSNotificationService.testEmailsSentCount;
        Test.startTest();
        PatientAdmissionHandler.handleAfterUpdate(
            new List<Admission__c>{ updatedAdmission },
            new Map<Id, Admission__c>{ admission.Id => admission }
        );
        Test.stopTest();

        System.assert(
            HMSNotificationService.testEmailsSentCount > emailsBefore,
            'Assigning a bed on admission should notify the ward manager.'
        );
    }

    @IsTest
    static void testDispatchAdmissionNotificationType() {
        Department__c department = createDepartment('Dispatch Adm Dept');
        Doctor__c doctor = createDoctor('Dr Dispatch Adm', department.Id, 'joshiprashant.0911@gmail.com');
        Patient__c patient = createPatient('Dispatch Adm Patient');
        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Status__c = 'Draft',
            Admission_Date_Time__c = System.now()
        );
        insert admission;

        Test.startTest();
        HMSNotificationService.dispatch(
            HMSNotificationQueueable.NotificationType.DOCTOR_ADMISSION,
            new Set<Id>{ admission.Id }
        );
        Test.stopTest();

        assertEmailSent('Dispatch should send doctor admission email.');
    }
}
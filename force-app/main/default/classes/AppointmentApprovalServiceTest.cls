@IsTest
private class AppointmentApprovalServiceTest {

    private static void setCalloutMock() {
        Test.setMock(HttpCalloutMock.class, new WhatsAppCalloutMock());
    }

    private static Appointment__c createPendingRequest() {
        Department__c cardiology = new Department__c(Name = 'Cardiology', Is_Medical_Department__c = true);
        insert cardiology;

        Staff__c staff = new Staff__c(
            Name = 'Dr Staff User',
            Email__c = 'doctor.staff@example.com',
            Salesforce_User__c = UserInfo.getUserId(),
            Status__c = 'Active'
        );
        insert staff;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr Approval Test',
            Department__c = cardiology.Id,
            Availability_Status__c = 'Available',
            Active__c = true,
            Available_Slots_Config__c = '09:00 - 09:30',
            Start_Time__c = Time.newInstance(9, 0, 0, 0),
            End_Time__c = Time.newInstance(17, 0, 0, 0),
            Consultation_Duration__c = 30,
            Max_Daily_Appointments__c = 20,
            Monday__c = true,
            Tuesday__c = true,
            Wednesday__c = true,
            Thursday__c = true,
            Friday__c = true,
            Saturday__c = true,
            Sunday__c = true,
            Available_Days__c = 'Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday',
            Staff__c = staff.Id
        );
        insert doctor;

        Patient__c patient = new Patient__c(
            Name = 'Approval Patient',
            Status__c = 'Active',
            Email__c = 'patient.approval@example.com',
            Phone__c = '9380653724'
        );
        insert patient;

        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = cardiology.Id,
            Appointment_Date__c = Date.today().addDays(2),
            Appointment_Date_Time__c = Datetime.newInstance(Date.today().addDays(2), Time.newInstance(9, 0, 0, 0)),
            Appointment_Time__c = '09:00',
            Selected_Slot__c = '09:00 - 09:30',
            Appointment_Type__c = 'OPD',
            Status__c = 'Requested',
            Source__c = 'Agent'
        );
        insert appt;
        return appt;
    }

    @IsTest
    static void testListPendingRequestsForCurrentDoctor() {
        setCalloutMock();
        createPendingRequest();

        Test.startTest();
        List<AppointmentApprovalService.PendingRequest> requests =
            AppointmentApprovalService.listPendingRequestsForCurrentDoctor();
        Test.stopTest();

        System.assertEquals(1, requests.size());
        System.assertEquals('Approval Patient', requests[0].patientName);
    }

    @IsTest
    static void testApproveRequest() {
        setCalloutMock();
        Appointment__c appt = createPendingRequest();

        Test.startTest();
        Appointment__c approved = AppointmentApprovalService.approveRequest(appt.Id);
        Test.stopTest();

        System.assertEquals('Confirmed', approved.Status__c);
        System.assertEquals('Confirmed', [
            SELECT Status__c FROM Appointment__c WHERE Id = :appt.Id
        ].Status__c);
    }

    @IsTest
    static void testRejectRequest() {
        setCalloutMock();
        Appointment__c appt = createPendingRequest();

        Test.startTest();
        Appointment__c rejected = AppointmentApprovalService.rejectRequest(
            appt.Id,
            'Doctor unavailable that day'
        );
        Test.stopTest();

        System.assertEquals('Rejected', rejected.Status__c);
        Appointment__c refreshed = [
            SELECT Status__c, Rejection_Reason__c
            FROM Appointment__c
            WHERE Id = :appt.Id
        ];
        System.assertEquals('Rejected', refreshed.Status__c);
        System.assertEquals('Doctor unavailable that day', refreshed.Rejection_Reason__c);
    }

    @IsTest
    static void testApproveRequestWithReceptionSourceAndMismatchedDates() {
        setCalloutMock();
        Appointment__c appt = createPendingRequest();
        appt.Source__c = 'Reception';
        update appt;

        appt.Appointment_Date__c = Date.today().addDays(5);
        update appt;

        Test.startTest();
        Appointment__c approved = AppointmentApprovalService.approveRequest(appt.Id);
        Test.stopTest();

        System.assertEquals('Confirmed', approved.Status__c);
        Appointment__c refreshed = [
            SELECT Status__c, Appointment_Date__c, Appointment_Date_Time__c
            FROM Appointment__c
            WHERE Id = :appt.Id
        ];
        System.assertEquals('Confirmed', refreshed.Status__c);
        System.assertEquals(Date.today().addDays(5), refreshed.Appointment_Date__c);
    }

    @IsTest
    static void testRejectRequestByOtherDoctorBlocked() {
        setCalloutMock();
        Appointment__c appt = createPendingRequest();

        Staff__c otherStaff = new Staff__c(
            Name = 'Other Staff',
            Email__c = 'other.staff@example.com',
            Status__c = 'Active'
        );
        insert otherStaff;

        User otherUser = createStandardUser('otherdoctor@test.com');
        otherStaff.Salesforce_User__c = otherUser.Id;
        update otherStaff;

        Doctor__c otherDoctor = new Doctor__c(
            Name = 'Dr Other',
            Department__c = appt.Department__c,
            Availability_Status__c = 'Available',
            Active__c = true,
            Staff__c = otherStaff.Id
        );
        insert otherDoctor;

        Boolean thrown = false;
        System.runAs(otherUser) {
            Test.startTest();
            try {
                AppointmentApprovalService.rejectRequest(appt.Id, 'Not mine');
            } catch (AppointmentBookingException ex) {
                thrown = true;
                System.assert(ex.getMessage().contains('assigned to you'));
            }
            Test.stopTest();
        }
        System.assertEquals(true, thrown);
    }

    private static User createStandardUser(String email) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'odoc',
            Email = email,
            EmailEncodingKey = 'UTF-8',
            LastName = 'OtherDoctor',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = email + System.currentTimeMillis()
        );
        insert u;
        return u;
    }
}
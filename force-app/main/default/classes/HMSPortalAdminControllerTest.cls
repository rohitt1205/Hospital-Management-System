@isTest
private class HMSPortalAdminControllerTest {

    private static void setCalloutMock() {
        Test.setMock(HttpCalloutMock.class, new WhatsAppCalloutMock());
    }

    private static Appointment__c createTestAppointment(String statusValue) {
        Department__c dept = new Department__c(Name = 'Admin Test Dept', Is_Medical_Department__c = true);
        insert dept;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr Admin Test',
            Department__c = dept.Id,
            Availability_Status__c = 'Available',
            Active__c = true
        );
        insert doctor;

        Patient__c patient = new Patient__c(
            Name = 'Admin Appt Patient',
            Status__c = 'Active',
            Email__c = 'admin.appt@example.invalid'
        );
        insert patient;

        Date apptDate = Date.today().addDays(3);
        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = dept.Id,
            Appointment_Date__c = apptDate,
            Appointment_Date_Time__c = Datetime.newInstance(apptDate, Time.newInstance(10, 0, 0, 0)),
            Appointment_Time__c = '10:00',
            Appointment_Type__c = 'OPD',
            Status__c = statusValue
        );
        insert appt;
        return appt;
    }

    @isTest
    static void staffCanSearchAndSavePatients() {
        Patient__c existing = new Patient__c(
            Name = 'Portal Admin Test Patient',
            Email__c = 'portal.admin.test@example.invalid',
            Status__c = 'Active'
        );
        insert existing;

        Test.startTest();
        List<HMSPortalAdminController.PatientRow> rows =
            HMSPortalAdminController.searchPatients('Portal Admin Test');
        System.assert(!rows.isEmpty(), 'Search should find the test patient.');

        String payload = JSON.serialize(new Map<String, Object>{
            'id' => existing.Id,
            'name' => 'Portal Admin Test Patient Updated',
            'email' => 'portal.admin.test@example.invalid',
            'phone' => '9999999999',
            'status' => 'Active'
        });
        HMSPortalAdminController.PatientRow saved =
            HMSPortalAdminController.savePatient(payload);

        List<HMSPortalAdminController.AppointmentRow> appts =
            HMSPortalAdminController.listAppointments('All');
        List<HMSPortalAdminController.PendingRequestRow> pending =
            HMSPortalAdminController.listPendingAppointmentRequests();
        List<HMSPortalAdminController.InvoiceRow> invoices =
            HMSPortalAdminController.listRecentInvoices();
        Test.stopTest();

        System.assertEquals('Portal Admin Test Patient Updated', saved.name);
        System.assertNotEquals(null, appts);
        System.assertNotEquals(null, pending);
        System.assertNotEquals(null, invoices);
    }

    @isTest
    static void staffCanCreatePatientAndUpdateRecords() {
        setCalloutMock();
        Patient__c patient = new Patient__c(
            Name = 'Created By Admin Portal',
            Email__c = 'created.admin@example.invalid',
            Status__c = 'Active',
            Patient_Approval_Status__c = 'Approved'
        );
        insert patient;

        Appointment__c appt = createTestAppointment('Requested');

        Invoice__c invoice = new Invoice__c(
            Patient__c = patient.Id,
            Payment_Status__c = 'Unpaid',
            Net_Payable__c = 1000
        );
        insert invoice;

        Test.startTest();
        HMSPortalAdminController.PatientRow created = HMSPortalAdminController.savePatient(
            JSON.serialize(new Map<String, Object>{
                'id' => patient.Id,
                'name' => 'Created By Admin Portal Updated',
                'email' => 'created.admin@example.invalid',
                'status' => 'Active'
            })
        );
        String apptMsg = HMSPortalAdminController.updateAppointmentStatus(appt.Id, 'Confirmed');
        String invMsg = HMSPortalAdminController.updateInvoicePaymentStatus(invoice.Id, 'Paid');
        List<HMSPortalAdminController.AppointmentRow> confirmedOnly =
            HMSPortalAdminController.listAppointments('Confirmed');
        String rejected = HMSPortalAdminController.rejectAppointmentRequest(
            createTestAppointment('Requested').Id,
            'Not available'
        );
        Test.stopTest();

        System.assertEquals('Created By Admin Portal Updated', created.name);
        System.assert(apptMsg.contains('Confirmed'));
        System.assert(invMsg.contains('Paid'));
        System.assert(!confirmedOnly.isEmpty());
        System.assert(rejected.contains('rejected'));
    }

    @isTest
    static void staffCanApprovePendingRequest() {
        setCalloutMock();
        Appointment__c appt = createTestAppointment('Requested');

        Test.startTest();
        String approved = HMSPortalAdminController.approveAppointmentRequest(appt.Id);
        Test.stopTest();

        System.assert(approved.contains('confirmed'));
    }

    @isTest
    static void listAppointmentsAllExcludesRequested() {
        Appointment__c pending = createTestAppointment('Requested');
        Appointment__c confirmed = createTestAppointment('Confirmed');

        Test.startTest();
        List<HMSPortalAdminController.AppointmentRow> allRows =
            HMSPortalAdminController.listAppointments('All');
        List<HMSPortalAdminController.AppointmentRow> requestedRows =
            HMSPortalAdminController.listAppointments('Requested');
        Test.stopTest();

        Set<String> allIds = new Set<String>();
        for (HMSPortalAdminController.AppointmentRow row : allRows) {
            allIds.add(row.id);
            System.assertNotEquals('Requested', row.status);
        }
        System.assert(allIds.contains(confirmed.Id), 'Confirmed appointment should appear in All.');
        System.assert(!allIds.contains(pending.Id), 'Requested appointment should stay in pending only.');
        System.assertEquals(1, requestedRows.size());
        System.assertEquals('Requested', requestedRows[0].status);
    }

    @isTest
    static void staffCanLoadAdminDashboardSummary() {
        insert new Patient__c(Name = 'Summary Patient', Status__c = 'Active');
        Test.startTest();
        Map<String, Integer> summary = HMSPortalAdminController.getAdminDashboardSummary();
        Test.stopTest();
        System.assert(summary.containsKey('totalPatients'));
        System.assert(summary.get('totalPatients') >= 1);
    }
}
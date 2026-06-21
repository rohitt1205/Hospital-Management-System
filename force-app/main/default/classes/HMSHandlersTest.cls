@IsTest
private class HMSHandlersTest {

    @IsTest
    static void testAdmissionEmailHandler() {
        Patient__c patient = new Patient__c(
            Name = 'Test Patient',
            Email__c = 'patient@test.com'
        );
        insert patient;

        Department__c dept = new Department__c(Name = 'General Medicine');
        insert dept;

        Ward__c ward = new Ward__c(
            Department__c = dept.Id,
            Capacity__c = 10,
            Current_Occupancy__c = 0
        );
        insert ward;

        Staff__c staff = new Staff__c(
            Name = 'Nurse One',
            Email__c = 'nurse@test.com',
            Department__c = dept.Id,
            Status__c = 'Active'
        );
        insert staff;

        Admission__c adm = new Admission__c(
            Patient__c = patient.Id,
            Ward__c = ward.Id,
            Admission_Type__c = 'Planned',
            Status__c = 'Admitted'
        );
        insert adm;

        AdmissionEmailHandler.AdmissionRequest req = new AdmissionEmailHandler.AdmissionRequest();
        req.admissionId = adm.Id;

        Test.startTest();
        AdmissionEmailHandler.sendWardStaffAlert(new List<AdmissionEmailHandler.AdmissionRequest>{ req });
        Test.stopTest();

        System.assert(true, 'Admission email handler should complete without error');
    }

    @IsTest
    static void testBillingInvoiceHandler() {
        Patient__c patient = new Patient__c(Name = 'Billing Patient');
        insert patient;

        Admission__c adm = new Admission__c(
            Patient__c = patient.Id,
            Stay_Cost__c = 1000,
            Procedure_Charges__c = 500,
            Lab_Charges__c = 200,
            Medicine_Charges__c = 100,
            Insurance_Covered_Amount__c = 300,
            Non_Billable_Amount__c = 50,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now()
        );
        insert adm;

        Department__c dept = new Department__c(Name = 'Inpatient General', Is_Medical_Department__c = true);
        insert dept;
        Ward__c ward = new Ward__c(Department__c = dept.Id, Capacity__c = 10, Current_Occupancy__c = 0);
        insert ward;
        Room__c room = new Room__c(Name = 'Room 102', Ward__c = ward.Id, Room_Type__c = 'private ac room with extra bed');
        insert room;
        Bed__c bed = new Bed__c(Name = 'Bed 102', Room__c = room.Id, Bed_Type__c = 'Normal', Status__c = 'Available');
        insert bed;
        Bed_Allocation__c bedAlloc = new Bed_Allocation__c(
            Admission__c = adm.Id,
            Patient__c = patient.Id,
            Bed__c = bed.Id,
            Start_Date_Time__c = Datetime.now(),
            Daily_Rate__c = 0,
            Status__c = 'Occupied'
        );
        insert bedAlloc;

        adm.Status__c = 'Discharged';
        adm.Actual_Discharge_Date_Time__c = Datetime.now().addDays(1);
        update adm;

        BillingInvoiceHandler.InvoiceRequest req = new BillingInvoiceHandler.InvoiceRequest();
        req.admissionId = adm.Id;

        Test.startTest();
        List<BillingInvoiceHandler.InvoiceResult> results =
            BillingInvoiceHandler.generateInvoice(new List<BillingInvoiceHandler.InvoiceRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess, 'Failed with: ' + results[0].errorMessage);
        System.assertNotEquals(null, results[0].invoiceId);
        System.assertEquals(Decimal.valueOf('500'), results[0].totalAmount);
    }

    @IsTest
    static void testDischargeSummaryHandler() {
        Patient__c patient = new Patient__c(Name = 'Discharge Patient');
        insert patient;

        Admission__c adm = new Admission__c(
            Patient__c = patient.Id,
            Diagnosis__c = 'Recovery',
            Bill_Amount__c = 2000,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now()
        );
        insert adm;

        Department__c dept = new Department__c(Name = 'Inpatient Diagnostics', Is_Medical_Department__c = true);
        insert dept;
        Ward__c ward = new Ward__c(Department__c = dept.Id, Capacity__c = 10, Current_Occupancy__c = 0);
        insert ward;
        Room__c room = new Room__c(Name = 'Room 103', Ward__c = ward.Id, Room_Type__c = 'private ac room with extra bed');
        insert room;
        Bed__c bed = new Bed__c(Name = 'Bed 103', Room__c = room.Id, Bed_Type__c = 'Normal', Status__c = 'Available');
        insert bed;
        Bed_Allocation__c bedAlloc = new Bed_Allocation__c(
            Admission__c = adm.Id,
            Patient__c = patient.Id,
            Bed__c = bed.Id,
            Start_Date_Time__c = Datetime.now(),
            Daily_Rate__c = 0,
            Status__c = 'Occupied'
        );
        insert bedAlloc;

        adm.Status__c = 'Discharged';
        adm.Actual_Discharge_Date_Time__c = Datetime.now().addDays(1);
        update adm;

        DischargeSummaryHandler.DischargeRequest req = new DischargeSummaryHandler.DischargeRequest();
        req.admissionId = adm.Id;

        Test.startTest();
        List<DischargeSummaryHandler.DischargeResult> results =
            DischargeSummaryHandler.generateDischargePDF(new List<DischargeSummaryHandler.DischargeRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess);
        System.assertNotEquals(null, results[0].contentDocumentId);
    }

    @IsTest
    static void testEmergencyAdmissionHandler() {
        Patient__c patient = new Patient__c(Name = 'Emergency Patient');
        insert patient;

        Department__c dept = new Department__c(Name = 'Emergency Dept');
        insert dept;

        Ward__c ward = new Ward__c(
            Department__c = dept.Id,
            Ward_Type__c = 'Emergency',
            Capacity__c = 5,
            Current_Occupancy__c = 1
        );
        insert ward;

        Staff__c staff = new Staff__c(
            Name = 'ER Nurse',
            Email__c = 'er@test.com',
            Department__c = dept.Id,
            Status__c = 'Active'
        );
        insert staff;

        Admission__c adm = new Admission__c(
            Patient__c = patient.Id,
            Ward__c = ward.Id,
            Admission_Type__c = 'Emergency',
            Priority__c = 'Critical',
            Status__c = 'Admitted'
        );
        insert adm;

        EmergencyAdmissionHandler.AdmissionRequest req = new EmergencyAdmissionHandler.AdmissionRequest();
        req.admissionId = adm.Id;

        Test.startTest();
        EmergencyAdmissionHandler.sendWardNotification(
            new List<EmergencyAdmissionHandler.AdmissionRequest>{ req }
        );
        Test.stopTest();

        System.assert(true, 'Emergency admission handler should complete without error');
    }

    @IsTest
    static void testOverdueInvoiceSmsHandler() {
        OverdueInvoiceSmsHandler.SmsRequest req = new OverdueInvoiceSmsHandler.SmsRequest();
        req.phoneNumber = '9999999999';
        req.patientName = 'SMS Patient';
        req.invoiceAmount = 1500;
        req.dueDate = Date.today().addDays(-5);
        req.invoiceNumber = 'INV-001';

        Test.startTest();
        List<OverdueInvoiceSmsHandler.SmsResult> results =
            OverdueInvoiceSmsHandler.sendSmsReminders(new List<OverdueInvoiceSmsHandler.SmsRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess);
    }
}
@IsTest
private class AdmissionBillingLedgerTest {
    private class LedgerMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }

    @IsTest
    static void admissionInvoiceAggregatesAllChargeSourcesAndSyncsPayment() {
        Patient__c patient = new Patient__c(
            Name = 'Ledger Billing Patient',
            Patient_Category__c = 'Normal',
            Phone__c = '9876543210'
        );
        insert patient;

        Insurance_Company__c company = new Insurance_Company__c(
            Name = 'Ledger Insurance',
            Active__c = true,
            Standard_Discount__c = 10
        );
        insert company;

        Insurance_Policy__c policy = new Insurance_Policy__c(
            Name = 'LEDGER-POLICY-001',
            Patient__c = patient.Id,
            Insurance_Company__c = company.Id
        );
        insert policy;

        Department__c department = new Department__c(Name = 'Ledger Cardiology', Is_Medical_Department__c = true);
        insert department;

        Staff__c staff = new Staff__c(Name = 'Ledger Doctor Staff', Department__c = department.Id, Status__c = 'Active');
        insert staff;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr. Ledger',
            Staff__c = staff.Id,
            Department__c = department.Id,
            Active__c = true,
            Consultation_Fee__c = 100
        );
        insert doctor;

        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date__c = Date.today(),
            Appointment_Time__c = '10:00',
            Status__c = 'Confirmed'
        );
        insert appointment;

        Ward__c ward = new Ward__c(Ward_Type__c = 'General', Capacity__c = 10);
        insert ward;

        Room__c room = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 10
        );
        insert room;

        Clinical_Service__c service = new Clinical_Service__c(
            Name = 'Ledger CT Scan',
            Department__c = department.Id,
            Active__c = true,
            Price__c = 300,
            Standard_Rate__c = 300
        );
        insert service;

        Lab_Test__c labTest = new Lab_Test__c(
            Name = 'Ledger CBC',
            Department__c = department.Id,
            Active__c = true,
            Standard_Rate__c = 250
        );
        insert labTest;

        Medicine__c medicine = new Medicine__c(
            Name = 'Ledger Medicine',
            Active__c = true,
            Unit_Price__c = 50,
            Stock_Quantity__c = 100
        );
        insert medicine;

        // Register the HTTP mock callout
        Test.setMock(HttpCalloutMock.class, new LedgerMock());

        InvoiceBillingService.bypassCalculation = true;
        Test.startTest();
        Datetime startDt = Datetime.now();
        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Appointment__c = appointment.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Ward__c = ward.Id,
            Room__c = room.Id,
            Insurance_Policy__c = policy.Id,
            Admission_Fee__c = 500,
            Admission_Date_Time__c = startDt,
            Status__c = 'Admitted',
            Phone__c = '9876543210'
        );
        insert admission;

        Invoice__c invoice = [
            SELECT Id
            FROM Invoice__c
            WHERE Admission__c = :admission.Id
            LIMIT 1
        ];
        invoice.Patient_Category__c = 'Civil Servant';
        update invoice;

        appointment.Status__c = 'Completed';
        update appointment;

        Bed_Allocation__c allocation = new Bed_Allocation__c(
            Admission__c = admission.Id,
            Patient__c = patient.Id,
            Room__c = room.Id,
            Room_Type__c = room.Room_Type__c,
            Bed_Number__c = '1',
            Start_Date_Time__c = startDt,
            End_Date_Time__c = startDt.addDays(2),
            Daily_Rate__c = 200,
            Status__c = 'Occupied'
        );
        insert allocation;

        Patient_Service__c patientService = new Patient_Service__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Doctor__c = doctor.Id,
            Clinical_Service__c = service.Id,
            Service_Date__c = Date.today()
        );
        insert patientService;
        Patient_Service__c reloadedService = [
            SELECT Clinical_Service__c
            FROM Patient_Service__c
            WHERE Id = :patientService.Id
        ];
        System.assertEquals(service.Id, reloadedService.Clinical_Service__c, 'Patient service must retain the selected clinical service.');

        Lab_Result__c labResult = new Lab_Result__c(
            Admission__c = admission.Id,
            Doctor__c = doctor.Id,
            Lab_Test__c = labTest.Id,
            Status__c = 'Completed'
        );
        insert labResult;
        labResult = [
            SELECT Patient__c
            FROM Lab_Result__c
            WHERE Id = :labResult.Id
        ];
        System.assertEquals(patient.Id, labResult.Patient__c, 'Lab result patient should be populated from admission.');

        Prescription__c prescription = new Prescription__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Doctor__c = doctor.Id,
            Medicine__c = medicine.Id,
            Quantity__c = 3,
            Status__c = 'Issued',
            Prescription_Date__c = Date.today()
        );
        insert prescription;
        InvoiceBillingService.bypassCalculation = false;
        InvoiceBillingService.calculateInvoiceTotals(new Set<Id>{ invoice.Id });
        Test.stopTest();

        invoice = [
            SELECT Gross_Amount__c, Insurance_Covered_Amount__c, Discount_Amount__c,
                   Net_Payable__c, Payment_Status__c
            FROM Invoice__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(1400, invoice.Gross_Amount__c, 'Gross must sum admission, appointment, room-priced accommodation, service, lab, and medicine.');
        System.assertEquals(140, invoice.Insurance_Covered_Amount__c, 'Insurance should be 10% of gross.');
        System.assertEquals(630, invoice.Discount_Amount__c, 'Civil Servant subsidy should be 50% after insurance.');
        System.assertEquals(630, invoice.Net_Payable__c, 'Net payable should be gross minus insurance minus subsidy.');
        System.assertEquals('Unpaid', invoice.Payment_Status__c);

        List<Invoice_Line_Item__c> billableItems = [
            SELECT Charge_Type__c, Line_Total__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoice.Id
            AND Charge_Type__c != 'Insurance Deduction'
        ];
        System.assertEquals(6, billableItems.size(), 'Each billable source should create one ledger line.');

        Payment__c payment = [
            SELECT Invoice__c, Amount__c, Status__c
            FROM Payment__c
            WHERE Invoice__c = :invoice.Id
            LIMIT 1
        ];
        System.assertEquals(invoice.Net_Payable__c, payment.Amount__c);
        System.assertEquals('Unpaid', payment.Status__c);

        Lab_Result__c followUpLab = new Lab_Result__c(
            Admission__c = admission.Id,
            Doctor__c = doctor.Id,
            Lab_Test__c = labTest.Id,
            Status__c = 'Ordered'
        );
        insert followUpLab;
        followUpLab.Status__c = 'Completed';
        update followUpLab;

        Integer labLineCount = [
            SELECT COUNT()
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoice.Id
            AND Charge_Type__c = 'Lab'
        ];
        System.assertEquals(2, labLineCount, 'Completed lab results should each create one lab ledger line.');
    }
}
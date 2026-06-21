@IsTest
private class BillingServicesTest {
    @IsTest
    static void admissionChargeOnInsertIsIdempotent() {
        Patient__c patient = new Patient__c(Name = 'Admission Billing Patient', Patient_Category__c = 'Normal');
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now()
        );
        insert admission;

        Test.startTest();
        InvoiceBillingService.handleAdmissionAfterInsert(new List<Admission__c>{ admission });
        InvoiceBillingService.handleAdmissionAfterInsert(new List<Admission__c>{ admission });
        Test.stopTest();

        List<Invoice__c> invoices = [
            SELECT Id, Gross_Amount__c, Net_Payable__c
            FROM Invoice__c
            WHERE Admission__c = :admission.Id
        ];
        System.assertEquals(1, invoices.size(), 'Admission insert billing must create one invoice.');
        System.assertEquals(Decimal.valueOf('500'), invoices[0].Gross_Amount__c);
        System.assertEquals(Decimal.valueOf('500'), invoices[0].Net_Payable__c);

        List<Invoice_Line_Item__c> lineItems = [
            SELECT Charge_Type__c, Line_Item_Key__c, Line_Amount__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoices[0].Id
        ];
        System.assertEquals(1, lineItems.size(), 'Repeated admission billing must not duplicate line items.');
        System.assertEquals('Admission', lineItems[0].Charge_Type__c);
        System.assertEquals(Decimal.valueOf('500'), lineItems[0].Line_Amount__c);
    }

    @IsTest
    static void legacyTriggerHandlersCreateExpectedCharges() {
        Patient__c patient = new Patient__c(Name = 'Legacy Billing Patient');
        insert patient;

        Department__c department = new Department__c(Name = 'Diagnostics', Is_Medical_Department__c = true);
        insert department;

        Staff__c staff = new Staff__c(Name = 'Lab Doctor', Department__c = department.Id, Status__c = 'Active');
        insert staff;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr. Legacy',
            Staff__c = staff.Id,
            Department__c = department.Id,
            Active__c = true
        );
        insert doctor;

        Lab_Test__c labTest = new Lab_Test__c(
            Name = 'Legacy CBC',
            Department__c = department.Id,
            Active__c = true,
            Standard_Rate__c = 400
        );
        insert labTest;

        Lab_Result__c labResult = new Lab_Result__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Lab_Test__c = labTest.Id,
            Status__c = 'Ordered'
        );
        insert labResult;

        Test.startTest();
        InvoiceBillingService.handleLabResultAfterInsert(new List<Lab_Result__c>{ labResult });
        labResult.Status__c = 'Completed';
        update labResult;
        InvoiceBillingService.handleLabResultAfterUpdate(
            new Map<Id, Lab_Result__c>{ labResult.Id => new Lab_Result__c(Id = labResult.Id, Status__c = 'Ordered') },
            new Map<Id, Lab_Result__c>{ labResult.Id => labResult }
        );
        Test.stopTest();

        List<Invoice_Line_Item__c> lineItems = [
            SELECT Charge_Type__c, Line_Amount__c
            FROM Invoice_Line_Item__c
            WHERE Charge_Type__c = 'Lab'
        ];
        System.assertEquals(1, lineItems.size(), 'Completed lab results should create one billing line item.');
        System.assertEquals(Decimal.valueOf('400'), lineItems[0].Line_Amount__c);
    }

    @IsTest
    static void dischargeBillingIsIdempotentAndCalculatesTotals() {
        Patient__c patient = new Patient__c(Name = 'Billing Patient', Patient_Category__c = 'Normal');
        insert patient;

        Department__c department = new Department__c(Name = 'Inpatient', Is_Medical_Department__c = true);
        insert department;

        Ward__c ward = new Ward__c(
            Department__c = department.Id,
            Capacity__c = 10,
            Current_Occupancy__c = 0
        );
        insert ward;

        Room__c room = new Room__c(
            Name = 'Room 101',
            Ward__c = ward.Id,
            Room_Type__c = 'private ac room with extra bed'
        );
        insert room;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Ward__c = ward.Id,
            Room__c = room.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now(),
            Insurance_Covered_Amount__c = 300
        );
        insert admission;

        Bed__c bed = new Bed__c(
            Name = 'Bed 101',
            Room__c = room.Id,
            Bed_Type__c = 'Normal',
            Status__c = 'Available'
        );
        insert bed;

        Bed_Allocation__c bedAlloc = new Bed_Allocation__c(
            Admission__c = admission.Id,
            Patient__c = patient.Id,
            Bed__c = bed.Id,
            Start_Date_Time__c = admission.Admission_Date_Time__c,
            Daily_Rate__c = 1000,
            Status__c = 'Occupied'
        );
        insert bedAlloc;

        // Now trigger the discharge update
        admission.Status__c = 'Discharged';
        admission.Actual_Discharge_Date_Time__c = Datetime.now().addDays(1);
        update admission;

        BillingInvoiceHandler.InvoiceRequest request = new BillingInvoiceHandler.InvoiceRequest();
        request.admissionId = admission.Id;

        Test.startTest();
        List<BillingInvoiceHandler.InvoiceResult> firstRun =
            BillingInvoiceHandler.generateInvoice(new List<BillingInvoiceHandler.InvoiceRequest>{ request });
        List<BillingInvoiceHandler.InvoiceResult> secondRun =
            BillingInvoiceHandler.generateInvoice(new List<BillingInvoiceHandler.InvoiceRequest>{ request });
        Test.stopTest();

        System.assertEquals(true, firstRun[0].isSuccess, 'First run failed: ' + firstRun[0].errorMessage);
        System.assertEquals(true, secondRun[0].isSuccess, 'Second run failed: ' + secondRun[0].errorMessage);
        System.assertEquals(firstRun[0].invoiceId, secondRun[0].invoiceId);

        List<Invoice__c> invoices = [
            SELECT Id, Gross_Amount__c, Insurance_Covered_Amount__c, Total_Amount__c, Net_Payable__c
            FROM Invoice__c
            WHERE Admission__c = :admission.Id
        ];
        System.assertEquals(1, invoices.size(), 'Repeated discharge generation must not create duplicate invoices.');
        System.assert(invoices[0].Gross_Amount__c > 0, 'Discharge invoice should have a positive gross amount.');
        System.assertEquals(
            invoices[0].Gross_Amount__c - invoices[0].Insurance_Covered_Amount__c,
            invoices[0].Net_Payable__c,
            'Net payable should subtract insurance from gross.'
        );
        System.assertEquals(invoices[0].Net_Payable__c, invoices[0].Total_Amount__c);

        List<Invoice_Line_Item__c> lineItems = [
            SELECT Charge_Type__c, Quantity__c, Unit_Rate__c, Line_Amount__c, Line_Item_Key__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoices[0].Id
        ];
        System.assertEquals(2, lineItems.size(), 'Admission and room charges should be unique.');
    }

    @IsTest
    static void serviceChargesCreateExpectedLineItems() {
        Patient__c patient = new Patient__c(Name = 'Outpatient Billing Patient');
        insert patient;

        Department__c department = new Department__c(Name = 'Clinical', Is_Medical_Department__c = true);
        insert department;

        Staff__c staff = new Staff__c(Name = 'Doctor Staff', Department__c = department.Id, Status__c = 'Active');
        insert staff;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr. Billing',
            Staff__c = staff.Id,
            Department__c = department.Id,
            Active__c = true,
            Consultation_Fee__c = 750
        );
        insert doctor;

        Lab_Test__c labTest = new Lab_Test__c(Name = 'CBC', Department__c = department.Id, Active__c = true, Standard_Rate__c = 450);
        insert labTest;

        Lab_Result__c labResult = new Lab_Result__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Lab_Test__c = labTest.Id,
            Status__c = 'Completed'
        );
        insert labResult;

        Medicine__c medicine = new Medicine__c(Name = 'Medicine A', Active__c = true, Unit_Price__c = 25, Stock_Quantity__c = 100);
        insert medicine;

        Prescription__c prescription = new Prescription__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Status__c = 'Issued',
            Prescription_Date__c = Date.today()
        );
        insert prescription;

        Prescription_Line_Item__c prescriptionLine = new Prescription_Line_Item__c(
            Prescription__c = prescription.Id,
            Medicine__c = medicine.Id,
            Quantity__c = 4
        );
        insert prescriptionLine;

        Test.startTest();
        ConsultationChargeService.createCharges(new Set<Id>());
        ConsultationBillingAction.createCharge(new List<ConsultationBillingAction.Request>());
        LabChargeService.createCharges(new Set<Id>{ labResult.Id });
        LabBillingAction.createCharge(new List<LabBillingAction.Request>());
        MedicineChargeService.createCharges(new Set<Id>{ prescriptionLine.Id });
        MedicineChargeService.createCharges(new Set<Id>{ prescriptionLine.Id });
        MedicineBillingAction.createCharge(new List<MedicineBillingAction.Request>());
        Test.stopTest();

        List<Invoice__c> invoices = [
            SELECT Id, Gross_Amount__c, Net_Payable__c
            FROM Invoice__c
            WHERE Patient__c = :patient.Id
            AND Admission__c = null
        ];
        System.assertEquals(1, invoices.size(), 'Same-day outpatient charges should share one patient invoice.');
        System.assertEquals(Decimal.valueOf('550'), invoices[0].Gross_Amount__c);
        System.assertEquals(Decimal.valueOf('550'), invoices[0].Net_Payable__c);

        List<Invoice_Line_Item__c> lineItems = [
            SELECT Charge_Type__c, Line_Amount__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoices[0].Id
        ];
        System.assertEquals(2, lineItems.size(), 'Repeated medicine charge processing must update, not duplicate.');
    }
}
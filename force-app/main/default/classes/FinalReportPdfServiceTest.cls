@IsTest
private class FinalReportPdfServiceTest {

    @IsTest
    static void buildsFullReportContext() {
        Department__c department = new Department__c(
            Name = 'PDF Department',
            Is_Medical_Department__c = true
        );
        insert department;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr PDF Test',
            Department__c = department.Id,
            Active__c = true,
            Availability_Status__c = 'Available'
        );
        insert doctor;

        Patient__c patient = new Patient__c(
            Name = 'PDF Service Patient',
            Email__c = 'pdf.service@test.hms',
            Phone__c = '+919876543210',
            Gender__c = 'Female',
            Blood_Group__c = 'A+',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId()
        );
        insert patient;

        Date apptDate = Date.today();
        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment_Date__c = apptDate,
            Appointment_Time__c = '10:00',
            Appointment_Date_Time__c = Datetime.newInstance(apptDate, Time.newInstance(10, 0, 0, 0)),
            Symptoms__c = 'Cough and cold',
            Status__c = 'Requested',
            Source__c = 'Agent'
        );
        insert appointment;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = department.Id,
            Appointment__c = appointment.Id,
            Admission_Date_Time__c = Datetime.now(),
            Diagnosis__c = 'Acute bronchitis',
            Status__c = 'Admitted'
        );
        insert admission;

        Lab_Test__c labTest = new Lab_Test__c(
            Name = 'HB1',
            Department__c = department.Id,
            Active__c = true,
            Standard_Rate__c = 500
        );
        insert labTest;

        insert new Lab_Result__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Doctor__c = doctor.Id,
            Lab_Test__c = labTest.Id,
            Result_Summary__c = 'Within range',
            Status__c = 'Completed'
        );

        Prescription__c prescription = new Prescription__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Status__c = 'Issued',
            Prescription_Date__c = Date.today(),
            Instructions__c = 'After food'
        );
        insert prescription;

        Medicine__c medicine = new Medicine__c(
            Name = 'Pantoprazole 40mg',
            Active__c = true,
            Unit_Price__c = 25,
            Stock_Quantity__c = 100
        );
        insert medicine;

        insert new Prescription_Line_Item__c(
            Prescription__c = prescription.Id,
            Medicine__c = medicine.Id,
            Quantity__c = 10,
            Frequency__c = 'Daily',
            Duration_Days__c = 7
        );

        Invoice__c invoice = new Invoice__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Gross_Amount__c = 1000,
            Insurance_Covered_Amount__c = 200,
            Discount_Amount__c = 50,
            Non_Billable_Deduction__c = 0,
            Net_Payable__c = 750,
            Payment_Status__c = 'Paid'
        );
        insert invoice;

        insert new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Charge_Type__c = 'Admission',
            Description__c = 'Admission Fee',
            Quantity__c = 1,
            Unit_Price__c = 1000,
            Line_Total__c = 1000,
            Line_Amount__c = 1000
        );

        Final_Report__c report = [
            SELECT Id
            FROM Final_Report__c
            WHERE Appointment__c = :appointment.Id
            LIMIT 1
        ];
        report.Summary__c = 'Stable recovery.';
        report.Discharge_Advice__c = 'Rest for one week.';
        report.Status__c = 'Draft';
        update report;

        Final_Report__c loaded = FinalReportPdfService.queryReport(report.Id);
        Test.startTest();
        FinalReportPdfService.PdfContext ctx = FinalReportPdfService.buildContext(loaded);
        Test.stopTest();

        System.assertEquals(report.Id, ctx.report.Id);
        System.assertEquals(1, ctx.labs.size());
        System.assertEquals(1, ctx.medicines.size());
        System.assertEquals(1, ctx.billingLines.size());
        System.assertEquals(true, ctx.stillAdmitted);
        System.assertEquals('Still Admitted', ctx.dischargeDateText);
        System.assertNotEquals(null, ctx.invoice);

        PageReference pageRef = Page.FinalReportPdf;
        pageRef.getParameters().put('id', report.Id);
        Test.setCurrentPage(pageRef);
        FinalReportPdfController controller = new FinalReportPdfController();
        System.assertEquals(true, controller.ready);
        System.assertEquals('badge badge-draft', controller.getStatusBadgeClass());
        System.assert(controller.getGrossTotal() > 0);
        System.assert(controller.getInsuranceCoverage() >= 0);
        System.assert(controller.getGovernmentSubsidy() >= 0);
        System.assert(controller.getNonBillableDeductions() >= 0);
        System.assert(controller.getNetPayable() >= 0);
        System.assertNotEquals(null, controller.getAppointmentDoctorName());
        System.assertNotEquals(null, controller.getTreatingDoctorName());
        System.assertNotEquals(null, controller.getPaymentStatus());
        System.assertEquals('—', controller.displayValue(''));
        System.assertEquals('Dr. PDF Test', controller.displayValue('Dr. PDF Test'));
    }

    @IsTest
    static void formatsDischargedAdmissionAndBillingGetters() {
        Patient__c patient = new Patient__c(
            Name = 'PDF Discharged Patient',
            Email__c = 'pdf.discharged@test.hms',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId()
        );
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Admission_Date_Time__c = Datetime.now(),
            Actual_Discharge_Date_Time__c = Datetime.now().addHours(2),
            Status__c = 'Discharged'
        );
        insert admission;

        Invoice__c invoice = new Invoice__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Gross_Amount__c = 500,
            Insurance_Covered_Amount__c = 100,
            Discount_Amount__c = 25,
            Non_Billable_Deduction__c = 5,
            Net_Payable__c = 370,
            Payment_Status__c = 'Paid'
        );
        insert invoice;
        invoice.Gross_Amount__c = 500;
        invoice.Insurance_Covered_Amount__c = 100;
        invoice.Discount_Amount__c = 25;
        invoice.Non_Billable_Deduction__c = 5;
        invoice.Net_Payable__c = 370;
        invoice.Payment_Status__c = 'Paid';
        update invoice;

        Final_Report__c report = [
            SELECT Id
            FROM Final_Report__c
            WHERE Admission__c = :admission.Id
            LIMIT 1
        ];
        report.Summary__c = 'Discharged well.';
        report.Status__c = 'Final';
        update report;

        FinalReportPdfService.PdfContext ctx = FinalReportPdfService.buildContext(
            FinalReportPdfService.queryReport(report.Id)
        );
        System.assertEquals(false, ctx.stillAdmitted);
        System.assertNotEquals('Still Admitted', ctx.dischargeDateText);

        PageReference pageRef = Page.FinalReportPdf;
        pageRef.getParameters().put('id', report.Id);
        Test.setCurrentPage(pageRef);
        FinalReportPdfController controller = new FinalReportPdfController();

        Invoice__c billed = [
            SELECT Name, Gross_Amount__c, Insurance_Covered_Amount__c, Discount_Amount__c,
                   Non_Billable_Deduction__c, Net_Payable__c, Payment_Status__c
            FROM Invoice__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(true, controller.ready);
        System.assertEquals('badge badge-final', controller.getStatusBadgeClass());
        System.assertNotEquals(null, controller.context.invoice);
        System.assertEquals(billed.Name, controller.getInvoiceNumber());
        System.assertEquals(billed.Gross_Amount__c, controller.getGrossTotal());
        System.assertEquals(billed.Net_Payable__c, controller.getNetPayable());
        System.assertEquals('pay-badge pay-paid', controller.getPaymentBadgeClass());
        System.assertNotEquals(null, controller.getTreatingDoctorName());
    }

    @IsTest
    static void buildsPatientOnlyContextWithoutAdmission() {
        Patient__c patient = new Patient__c(
            Name = 'PDF Only Patient',
            Email__c = 'pdf.only@test.hms',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId()
        );
        insert patient;

        Final_Report__c report = new Final_Report__c(
            Patient__c = patient.Id,
            Summary__c = 'Outpatient summary',
            Status__c = 'Shared With Patient'
        );
        insert report;

        FinalReportPdfService.PdfContext ctx = FinalReportPdfService.buildContext(
            FinalReportPdfService.queryReport(report.Id)
        );

        System.assertEquals(false, ctx.stillAdmitted);
        System.assertEquals(0, ctx.labs.size());
        System.assertEquals(0, ctx.medicines.size());
    }

    @IsTest
    static void pdfControllerHandlesMissingReport() {
        PageReference pageRef = Page.FinalReportPdf;
        Test.setCurrentPage(pageRef);
        FinalReportPdfController controller = new FinalReportPdfController();
        System.assertEquals(false, controller.ready);
    }

    @IsTest
    static void pdfControllerCoversDraftAndCalculatedTotals() {
        Patient__c patient = new Patient__c(
            Name = 'PDF Draft Patient',
            Email__c = 'pdf.draft@test.hms',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId()
        );
        insert patient;

        Final_Report__c report = new Final_Report__c(
            Patient__c = patient.Id,
            Summary__c = 'Draft report',
            Status__c = 'Draft'
        );
        insert report;

        Invoice__c invoice = new Invoice__c(
            Patient__c = patient.Id,
            Payment_Status__c = 'Unpaid'
        );
        insert invoice;
        insert new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Charge_Type__c = 'Appointment',
            Description__c = 'Consultation',
            Quantity__c = 1,
            Unit_Price__c = 920,
            Line_Total__c = 920,
            Line_Amount__c = 920
        );

        PageReference pageRef = Page.FinalReportPdf;
        pageRef.getParameters().put('id', report.Id);
        Test.setCurrentPage(pageRef);
        FinalReportPdfController controller = new FinalReportPdfController();

        System.assertEquals(true, controller.ready);
        System.assertEquals('badge badge-draft', controller.getStatusBadgeClass());
        System.assertEquals('pay-badge pay-unpaid', controller.getPaymentBadgeClass());
        System.assertEquals('UNPAID', controller.getPaymentStatus());
        System.assert(controller.getGrossTotal() >= 0);
        System.assert(controller.getNetPayable() >= 0);
    }
}
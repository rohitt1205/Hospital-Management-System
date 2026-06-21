@IsTest
private class FinalReportAutomationHandlerTest {

    @TestSetup
    static void setupData() {
        Department__c department = new Department__c(
            Name = 'Cardiology',
            Is_Medical_Department__c = true
        );
        insert department;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr Final Report Test',
            Department__c = department.Id,
            Active__c = true,
            Availability_Status__c = 'Available'
        );
        insert doctor;

        Patient__c patient = new Patient__c(
            Name = 'Final Report Patient',
            Status__c = 'Active',
            Phone__c = '9000000099'
        );
        insert patient;
    }

    @IsTest
    static void testHandleAppointmentInsertCreatesFinalReport() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Final Report Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Final Report Test' LIMIT 1];
        Date targetDate = Date.today().addDays(3);

        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Date__c = targetDate,
            Appointment_Time__c = '10:00',
            Appointment_Date_Time__c = Datetime.newInstance(targetDate, Time.newInstance(10, 0, 0, 0)),
            Status__c = 'Requested',
            Source__c = 'Agent'
        );

        Test.startTest();
        insert appt;
        Test.stopTest();

        List<Final_Report__c> reports = [
            SELECT Id, Appointment__c, Patient__c, Doctor__c, Status__c
            FROM Final_Report__c
            WHERE Appointment__c = :appt.Id
        ];
        System.assertEquals(1, reports.size(), 'Appointment insert should create one final report.');
        System.assertEquals('Draft', reports[0].Status__c);
        System.assertEquals(patient.Id, reports[0].Patient__c);
        System.assertEquals(doctor.Id, reports[0].Doctor__c);
    }

    @IsTest
    static void testHandleAdmissionInsertLinksExistingFinalReport() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Final Report Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Final Report Test' LIMIT 1];
        Date targetDate = Date.today().addDays(4);

        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Date__c = targetDate,
            Appointment_Time__c = '11:00',
            Appointment_Date_Time__c = Datetime.newInstance(targetDate, Time.newInstance(11, 0, 0, 0)),
            Status__c = 'Requested',
            Source__c = 'Agent'
        );
        insert appt;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment__c = appt.Id,
            Admission_Date_Time__c = Datetime.newInstance(targetDate, Time.newInstance(11, 0, 0, 0)),
            Status__c = 'Admitted'
        );
        insert admission;

        Test.startTest();
        FinalReportAutomationHandler.handleAdmissionInsert(new List<Admission__c>{ admission });
        Test.stopTest();

        Final_Report__c report = [
            SELECT Id, Admission__c, Appointment__c
            FROM Final_Report__c
            WHERE Appointment__c = :appt.Id
            LIMIT 1
        ];
        System.assertEquals(appt.Id, report.Appointment__c);
        System.assertEquals(admission.Id, report.Admission__c);
    }

    @IsTest
    static void testHandleFinalReportBeforeSavePopulatesLookups() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Final Report Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Final Report Test' LIMIT 1];
        Date targetDate = Date.today().addDays(5);

        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Date__c = targetDate,
            Appointment_Time__c = '09:00',
            Appointment_Date_Time__c = Datetime.newInstance(targetDate, Time.newInstance(9, 0, 0, 0)),
            Status__c = 'Requested',
            Source__c = 'Agent'
        );
        insert appt;

        Final_Report__c report = new Final_Report__c(
            Appointment__c = appt.Id,
            Status__c = 'Draft'
        );

        Test.startTest();
        FinalReportAutomationHandler.handleFinalReportBeforeSave(new List<Final_Report__c>{ report });
        Test.stopTest();

        System.assertEquals(patient.Id, report.Patient__c);
        System.assertEquals(doctor.Id, report.Doctor__c);
    }

    @IsTest
    static void testHandleAdmissionInsertCreatesReportWithoutAppointment() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Final Report Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Final Report Test' LIMIT 1];

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Admission_Date_Time__c = Datetime.now().addDays(1),
            Status__c = 'Admitted'
        );
        insert admission;

        Test.startTest();
        FinalReportAutomationHandler.handleAdmissionInsert(new List<Admission__c>{ admission });
        Test.stopTest();

        List<Final_Report__c> reports = [
            SELECT Id, Admission__c, Patient__c
            FROM Final_Report__c
            WHERE Admission__c = :admission.Id
        ];
        System.assert(!reports.isEmpty(), 'Admission without appointment should create a final report.');
        System.assertEquals(patient.Id, reports[0].Patient__c);
    }

    @IsTest
    static void testFinalReportPDFGenerationAndWhatsAppSend() {
        Test.setMock(HttpCalloutMock.class, new WhatsAppCalloutMock());

        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Final Report Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Final Report Test' LIMIT 1];
        Date targetDate = Date.today().addDays(3);

        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Date__c = targetDate,
            Appointment_Time__c = '10:00',
            Appointment_Date_Time__c = Datetime.newInstance(targetDate, Time.newInstance(10, 0, 0, 0)),
            Status__c = 'Requested',
            Source__c = 'Agent'
        );
        insert appt;

        List<Final_Report__c> reports = [
            SELECT Id, Appointment__c, Patient__c, Doctor__c, Status__c
            FROM Final_Report__c
            WHERE Appointment__c = :appt.Id
        ];
        System.assertEquals(1, reports.size());
        Id reportId = reports[0].Id;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment__c = appt.Id,
            Admission_Date_Time__c = Datetime.newInstance(targetDate, Time.newInstance(10, 0, 0, 0)),
            Status__c = 'Admitted'
        );
        insert admission;

        reports[0].Admission__c = admission.Id;
        update reports[0];

        Invoice__c invoice = new Invoice__c(
            Admission__c = admission.Id,
            Gross_Amount__c = 100,
            Discount_Amount__c = 10,
            Insurance_Covered_Amount__c = 20,
            Non_Billable_Deduction__c = 5,
            Net_Payable__c = 65,
            Payment_Status__c = 'Unpaid'
        );
        insert invoice;

        Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Charge_Type__c = 'Room Rent',
            Description__c = 'Standard Room',
            Quantity__c = 1,
            Unit_Price__c = 100,
            Line_Total__c = 100
        );
        insert lineItem;

        Test.startTest();
        
        PageReference pageRef = Page.FinalReportPDFPage;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('id', reportId);
        
        FinalReportPdfController controller = new FinalReportPdfController();
        System.assertNotEquals(null, controller.report, 'Controller should retrieve the report details.');
        System.assertEquals(true, controller.hasAdmission);
        System.assertEquals(true, controller.hasInvoice);
        System.assertEquals(true, controller.hasInvoiceLineItems);
        
        SendFinalReportWhatsApp.sendReport(reportId, true);
        
        WhatsAppService.sendWhatsAppMessage('9000000099', 'Hello', 'http://example.com/file.pdf');

        Test.stopTest();
    }
}
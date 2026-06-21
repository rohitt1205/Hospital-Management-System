@IsTest
private class HMSFinalReportPortalControllerTest {

    @IsTest
    static void portalPatientCanViewDownloadAndWhatsAppReport() {
        Patient__c patient = new Patient__c(
            Name = 'Final Report Portal Patient',
            Email__c = 'final.report@test.hms',
            Phone__c = '+919876543210',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId()
        );
        insert patient;

        Final_Report__c report = new Final_Report__c(
            Patient__c = patient.Id,
            Summary__c = 'Patient recovered well.',
            Discharge_Advice__c = 'Follow up in two weeks.',
            Status__c = 'Final'
        );
        insert report;

        Test.setMock(HttpCalloutMock.class, new WhatsAppCalloutMock());

        Test.startTest();
        Map<String, Object> detail = HMSFinalReportPortalController.getFinalReportDetail(report.Id);
        String pdfUrl = HMSFinalReportPortalController.getFinalReportPdfUrl(report.Id);
        String whatsappResult = HMSFinalReportPortalController.sendFinalReportWhatsApp(report.Id);
        Test.stopTest();

        System.assertEquals(report.Id, detail.get('recordId'));
        System.assertEquals('Patient recovered well.', detail.get('summary'));
        System.assert(String.isNotBlank(pdfUrl), 'PDF URL should be returned.');
        System.assert(pdfUrl.toLowerCase().contains('finalreportpdf'), 'PDF URL should target the VF page.');
        System.assertEquals('sent', whatsappResult);
    }

    @IsTest
    static void pdfControllerLoadsAuthorizedReport() {
        Patient__c patient = new Patient__c(
            Name = 'PDF Portal Patient',
            Email__c = 'pdf.report@test.hms',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId()
        );
        insert patient;

        Final_Report__c report = new Final_Report__c(
            Patient__c = patient.Id,
            Summary__c = 'Ready for download.',
            Status__c = 'Final'
        );
        insert report;

        PageReference pageRef = Page.FinalReportPdf;
        pageRef.getParameters().put('id', report.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        FinalReportPdfController controller = new FinalReportPdfController();
        Test.stopTest();

        System.assertEquals(true, controller.ready, 'Authorized patient should load the PDF report.');
        System.assertNotEquals(null, controller.context);
    }

    @IsTest
    static void pdfControllerRejectsMissingOrForeignReport() {
        PageReference missingIdPage = Page.FinalReportPdf;
        Test.setCurrentPage(missingIdPage);
        FinalReportPdfController missingIdController = new FinalReportPdfController();
        System.assertEquals(false, missingIdController.ready);

        Patient__c mine = new Patient__c(
            Name = 'Mine',
            Email__c = 'mine.pdf@test.hms',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId()
        );
        Patient__c other = new Patient__c(
            Name = 'Other',
            Email__c = 'other.pdf@test.hms',
            Status__c = 'Active'
        );
        insert new List<Patient__c>{ mine, other };

        Final_Report__c foreignReport = new Final_Report__c(
            Patient__c = other.Id,
            Summary__c = 'Private',
            Status__c = 'Final'
        );
        insert foreignReport;

        PageReference foreignPage = Page.FinalReportPdf;
        foreignPage.getParameters().put('id', foreignReport.Id);
        Test.setCurrentPage(foreignPage);
        FinalReportPdfController foreignController = new FinalReportPdfController();
        System.assertEquals(false, foreignController.ready);
    }

    @IsTest
    static void rejectsReportForDifferentPatient() {
        Patient__c mine = new Patient__c(
            Name = 'My Patient',
            Email__c = 'mine@test.hms',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId()
        );
        Patient__c other = new Patient__c(
            Name = 'Other Patient',
            Email__c = 'other@test.hms',
            Status__c = 'Active'
        );
        insert new List<Patient__c>{ mine, other };

        Final_Report__c report = new Final_Report__c(
            Patient__c = other.Id,
            Summary__c = 'Private report',
            Status__c = 'Final'
        );
        insert report;

        Boolean denied = false;
        try {
            HMSFinalReportPortalController.getFinalReportDetail(report.Id);
        } catch (AuraHandledException e) {
            denied = true;
        }
        System.assert(denied, 'Portal user should not access another patient report.');
    }
}
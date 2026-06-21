/**
 * Patient portal actions for the single Final Report record (view, PDF, WhatsApp).
 */
public without sharing class HMSFinalReportPortalController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFinalReportDetail(Id reportId) {
        Final_Report__c report = loadAuthorizedReport(reportId);
        return toDetailMap(report);
    }

    @AuraEnabled
    public static String getFinalReportPdfUrl(Id reportId) {
        loadAuthorizedReport(reportId);
        return buildPdfUrl(reportId);
    }

    @AuraEnabled
    public static String sendFinalReportWhatsApp(Id reportId) {
        Final_Report__c report = loadAuthorizedReport(reportId);
        Patient__c patient = PatientPortalLinkService.resolveForRunningUser();
        if (patient == null || String.isBlank(patient.Phone__c)) {
            throw new AuraHandledException('Add a phone number to your patient profile to receive WhatsApp messages.');
        }

        String doctorName = report.Doctor__r != null ? report.Doctor__r.Name : 'Your care team';
        String summaryText = String.isBlank(report.Summary__c) ? 'Your hospital final report is ready.' : report.Summary__c;
        String pdfUrl = buildPdfUrl(reportId);

        String message =
            'HMS Hospital — Final Report\n\n' +
            'Report: ' + report.Name + '\n' +
            'Doctor: ' + doctorName + '\n' +
            'Status: ' + String.valueOf(report.Status__c) + '\n\n' +
            summaryText + '\n\n' +
            'Download PDF: ' + pdfUrl;

        WhatsAppService.sendWhatsAppMessage(patient.Phone__c, message);
        return 'sent';
    }

    private static Final_Report__c loadAuthorizedReport(Id reportId) {
        if (reportId == null) {
            throw new AuraHandledException('Report id is required.');
        }

        Patient__c patient = PatientPortalLinkService.resolveForRunningUser();
        if (patient == null) {
            throw new AuraHandledException('No patient record is linked to your portal login.');
        }

        List<Final_Report__c> reports = [
            SELECT Id, Name, Status__c, Summary__c, Discharge_Advice__c, CreatedDate,
                   Patient__c, Patient__r.Name, Patient__r.Patient_ID__c,
                   Doctor__c, Doctor__r.Name,
                   Admission__c, Admission__r.Name, Admission__r.Admission_Date_Time__c
            FROM Final_Report__c
            WHERE Id = :reportId
              AND Patient__c = :patient.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (reports.isEmpty()) {
            throw new AuraHandledException('You are not authorized to access this report.');
        }
        return reports[0];
    }

    private static Map<String, Object> toDetailMap(Final_Report__c report) {
        Map<String, Object> detail = new Map<String, Object>();
        detail.put('recordId', report.Id);
        detail.put('numberValue', report.Name);
        detail.put('status', report.Status__c);
        detail.put('summary', report.Summary__c);
        detail.put('dischargeAdvice', report.Discharge_Advice__c);
        detail.put('doctorName', report.Doctor__r != null ? report.Doctor__r.Name : null);
        detail.put('patientName', report.Patient__r != null ? report.Patient__r.Name : null);
        detail.put('patientId', report.Patient__r != null ? report.Patient__r.Patient_ID__c : null);
        detail.put('admissionName', report.Admission__r != null ? report.Admission__r.Name : null);
        detail.put('admissionDate', report.Admission__r != null ? report.Admission__r.Admission_Date_Time__c : null);
        detail.put('createdDate', report.CreatedDate);
        detail.put('pdfUrl', buildPdfUrl(report.Id));
        return detail;
    }

    private static String buildPdfUrl(Id reportId) {
        String pagePath = Page.FinalReportPdf.getUrl() + '?id=' + EncodingUtil.urlEncode(String.valueOf(reportId), 'UTF-8');
        if (!Test.isRunningTest() && String.isNotBlank(Site.getSiteId())) {
            return Site.getBaseUrl().removeEnd('/') + pagePath;
        }
        return URL.getOrgDomainUrl().toExternalForm().removeEnd('/') + pagePath;
    }
}
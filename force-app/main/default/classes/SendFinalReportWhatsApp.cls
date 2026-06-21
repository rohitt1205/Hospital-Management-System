public without sharing class SendFinalReportWhatsApp {

    @InvocableMethod(label='Send Final Report via WhatsApp' description='Sends a formatted WhatsApp summary of the Final Report to the patient upon discharge')
    public static void sendWhatsAppReportFlow(List<Id> admissionIds) {
        if (admissionIds == null || admissionIds.isEmpty()) {
            return;
        }
        
        List<Final_Report__c> reports = [
            SELECT Id 
            FROM Final_Report__c 
            WHERE Admission__c IN :admissionIds
        ];
        
        for (Final_Report__c report : reports) {
            sendReport(report.Id);
        }
    }
    
    public static void sendReport(Id reportId) {
        sendReport(reportId, true);
    }
    
    public static void sendReport(Id reportId, Boolean isAsync) {
        if (isAsync && !Test.isRunningTest()) {
            System.enqueueJob(new FinalReportPDFSendQueueable(reportId));
        } else {
            sendReportAsyncExecutor(reportId, isAsync);
        }
    }
    
    public static void sendReportAsyncExecutor(Id reportId, Boolean inAsyncJob) {
        Final_Report__c report;
        try {
            report = [
                SELECT Id, Name, Summary__c, Discharge_Advice__c, Status__c,
                       Patient__r.Name, Patient__r.Phone__c, Patient__r.Email__c, Patient__r.Gender__c,
                       Doctor__r.Name,
                       Admission__c, Admission__r.Name, Admission__r.Admission_Date_Time__c, Admission__r.Actual_Discharge_Date_Time__c, Admission__r.Diagnosis__c,
                       Appointment__c, Appointment__r.Name, Appointment__r.Appointment_Date__c, Appointment__r.Appointment_Time__c, Appointment__r.Symptoms__c, Appointment__r.Doctor__r.Name
                FROM Final_Report__c
                WHERE Id = :reportId
                LIMIT 1
            ];
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Failed to query Final Report record: ' + ex.getMessage());
            return;
        }
        
        try {
            sendPdfReport(report, inAsyncJob);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Failed to generate or send PDF Final Report, falling back to text summary: ' + ex.getMessage());
            sendTextSummary(report, inAsyncJob);
        }
    }
    
    private static void sendPdfReport(Final_Report__c report, Boolean inAsyncJob) {
        PageReference pdfPage = Page.FinalReportPDFPage;
        pdfPage.getParameters().put('id', report.Id);
        
        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('Test PDF Content');
        } else {
            pdfBlob = pdfPage.getContentAsPDF();
        }
        
        String patientName = report.Patient__r.Name != null ? report.Patient__r.Name.replace(' ', '_') : 'Patient';
        String formattedDate = System.today().format().replace('/', '_');
        String filename = 'Final_Medical_Report_' + patientName + '_' + formattedDate + '.pdf';
        
        ContentVersion cv = new ContentVersion();
        cv.Title = filename;
        cv.PathOnClient = filename;
        cv.VersionData = pdfBlob;
        cv.IsMajorVersion = true;
        insert cv;
        
        cv = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        
        ContentDistribution cd = new ContentDistribution();
        cd.Name = cv.Title;
        cd.ContentVersionId = cv.Id;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesLinkLatestVersion = true;
        cd.PreferencesNotifyOnVisit = false;
        cd.PreferencesPasswordRequired = false;
        cd.PreferencesAllowOriginalDownload = true;
        insert cd;
        
        cd = [SELECT Id, ContentDownloadUrl FROM ContentDistribution WHERE Id = :cd.Id LIMIT 1];
        String mediaUrl = cd.ContentDownloadUrl;
        
        String recipientPhone = report.Patient__r.Phone__c;
        if (String.isBlank(recipientPhone)) {
            recipientPhone = '9910154408'; // fallback testing number
        }
        
        String messageBody = 'Dear ' + report.Patient__r.Name + ', please find your final medical report attached below.';
        
        if (inAsyncJob && !Test.isRunningTest()) {
            System.enqueueJob(new FinalReportTwilioSendQueueable(recipientPhone, messageBody, mediaUrl));
        } else {
            if (Test.isRunningTest()) {
                WhatsAppService.sendWhatsAppMessage(recipientPhone, messageBody, mediaUrl);
            } else {
                WhatsAppService.sendWhatsAppMessageSync(recipientPhone, messageBody, mediaUrl);
            }
        }
    }
    
    private static void sendTextSummary(Final_Report__c report, Boolean inAsyncJob) {
        Id reportId = report.Id;
        Id admissionId = report.Admission__c;
        
        // Fetch Lab Results
        List<Lab_Result__c> labs = new List<Lab_Result__c>();
        if (admissionId != null) {
            labs = [
                SELECT Lab_Test__r.Name, Result_Summary__c, Status__c
                FROM Lab_Result__c
                WHERE Admission__c = :admissionId
            ];
        }
        
        // Fetch Prescriptions & line items (look up direct Admission + Medical Record linkages)
        Set<Id> prescriptionIds = new Set<Id>();
        if (admissionId != null) {
            for (Prescription__c p : [SELECT Id FROM Prescription__c WHERE Admission__c = :admissionId]) {
                prescriptionIds.add(p.Id);
            }
            for (Prescription__c p : [SELECT Id FROM Prescription__c WHERE Medical_Record__r.Admission__c = :admissionId]) {
                prescriptionIds.add(p.Id);
            }
        }
        if (report.Appointment__c != null) {
            for (Prescription__c p : [SELECT Id FROM Prescription__c WHERE Medical_Record__r.Appointment__c = :report.Appointment__c]) {
                prescriptionIds.add(p.Id);
            }
        }
        
        List<Prescription__c> prescriptions = new List<Prescription__c>();
        if (!prescriptionIds.isEmpty()) {
            prescriptions = [
                SELECT Medicine__r.Name, Instructions__c, Quantity__c, Unit_Price__c, Medicine__c, Total_Medicine_Bill__c,
                       (SELECT Medicine__r.Name, Dosage__c, Frequency__c, Duration_Days__c, Quantity__c FROM Prescription_Line_Items__r)
                FROM Prescription__c
                WHERE Id IN :prescriptionIds
            ];
        }
        
        // Fetch Invoice & line items
        Invoice__c invoice = null;
        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();
        if (admissionId != null) {
            List<Invoice__c> invoices = [
                SELECT Name, Gross_Amount__c, Insurance_Covered_Amount__c, Discount_Amount__c, Non_Billable_Deduction__c, Net_Amount__c, Net_Payable__c, Payment_Status__c
                FROM Invoice__c
                WHERE Admission__c = :admissionId
                LIMIT 1
            ];
            if (!invoices.isEmpty()) {
                invoice = invoices[0];
                lineItems = [
                    SELECT Charge_Type__c, Description__c, Quantity__c, Unit_Price__c, Line_Total__c
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__c = :invoice.Id
                ];
            }
        }
        
        // Build WhatsApp Message Body
        String messageBody = '📄 *FINAL MEDICAL REPORT - ' + report.Name + '*\n\n';
        
        // 1. Patient Demographics
        messageBody += '👤 *Patient Info:*\n';
        messageBody += 'Name: ' + report.Patient__r.Name + '\n';
        messageBody += 'Gender: ' + (report.Patient__r.Gender__c != null ? report.Patient__r.Gender__c : 'N/A') + '\n\n';
        
        // 2. Appointment Details
        if (report.Appointment__c != null) {
            messageBody += '📅 *Appointment Details:*\n';
            messageBody += 'No: ' + report.Appointment__r.Name + '\n';
            messageBody += 'Date: ' + report.Appointment__r.Appointment_Date__c + ' ' + (report.Appointment__r.Appointment_Time__c != null ? report.Appointment__r.Appointment_Time__c : '') + '\n';
            messageBody += 'Doctor: ' + report.Appointment__r.Doctor__r.Name + '\n';
            messageBody += 'Reason: ' + (report.Appointment__r.Symptoms__c != null ? report.Appointment__r.Symptoms__c : 'N/A') + '\n\n';
        }
        
        // 3. Admission & Discharge Details
        if (report.Admission__c != null) {
            messageBody += '🏥 *Admission Details:*\n';
            messageBody += 'No: ' + report.Admission__r.Name + '\n';
            messageBody += 'Admitted: ' + report.Admission__r.Admission_Date_Time__c + '\n';
            messageBody += 'Discharged: ' + (report.Admission__r.Actual_Discharge_Date_Time__c != null ? String.valueOf(report.Admission__r.Actual_Discharge_Date_Time__c) : 'Pending') + '\n';
            messageBody += 'Treating Doctor: ' + report.Doctor__r.Name + '\n';
            messageBody += 'Diagnosis: ' + (report.Admission__r.Diagnosis__c != null ? report.Admission__r.Diagnosis__c : 'N/A') + '\n\n';
        }
        
        // 4. Lab Results Section
        if (!labs.isEmpty()) {
            messageBody += '🧪 *Lab Test Results:*\n';
            for (Lab_Result__c lr : labs) {
                String testName = lr.Lab_Test__r.Name != null ? lr.Lab_Test__r.Name : 'Lab Test';
                String summary = lr.Result_Summary__c != null ? lr.Result_Summary__c : 'Pending';
                messageBody += '- ' + testName + ': ' + summary + '\n';
            }
            messageBody += '\n';
        }
        
        // 5. Prescription Details
        if (!prescriptions.isEmpty()) {
            messageBody += '💊 *Prescribed Medications:*\n';
            for (Prescription__c pr : prescriptions) {
                if (pr.Prescription_Line_Items__r != null && !pr.Prescription_Line_Items__r.isEmpty()) {
                    for (Prescription_Line_Item__c pli : pr.Prescription_Line_Items__r) {
                        String medName = pli.Medicine__r.Name != null ? pli.Medicine__r.Name : 'Medicine';
                        String dosage = pli.Dosage__c != null ? pli.Dosage__c : '';
                        String freq = pli.Frequency__c != null ? pli.Frequency__c : '';
                        String dur = pli.Duration_Days__c != null ? String.valueOf(pli.Duration_Days__c) + ' days' : '';
                        messageBody += '- ' + medName + ' (' + dosage + ' ' + freq + ' ' + dur + ')\n';
                    }
                } else if (pr.Medicine__r.Name != null) {
                    messageBody += '- ' + pr.Medicine__r.Name + ' (' + (pr.Instructions__c != null ? pr.Instructions__c : '') + ')\n';
                }
            }
            messageBody += '\n';
        }
        
        // 6. Invoice Line Items Section
        if (!lineItems.isEmpty()) {
            messageBody += '🧾 *Billing Details (Items):*\n';
            for (Invoice_Line_Item__c item : lineItems) {
                String descText = item.Description__c != null ? item.Description__c : item.Charge_Type__c;
                Decimal total = item.Line_Total__c != null ? item.Line_Total__c : 0;
                Decimal totalInr = total * 92;
                messageBody += '- ' + descText + ': ₹' + totalInr + '\n';
            }
            messageBody += '\n';
        }
        
        // 7. Final Billing Calculations
        if (invoice != null) {
            Decimal grossInr = (invoice.Gross_Amount__c != null ? invoice.Gross_Amount__c : 0) * 92;
            Decimal insuranceInr = (invoice.Insurance_Covered_Amount__c != null ? invoice.Insurance_Covered_Amount__c : 0) * 92;
            Decimal discountInr = (invoice.Discount_Amount__c != null ? invoice.Discount_Amount__c : 0) * 92;
            Decimal netPayableInr = (invoice.Net_Payable__c != null ? invoice.Net_Payable__c : 0) * 92;
            
            messageBody += '💰 *Billing Summary (' + invoice.Name + '):*\n';
            messageBody += 'Gross Amount: ₹' + grossInr + '\n';
            messageBody += 'Insurance Covered: ₹' + insuranceInr + '\n';
            messageBody += 'Discount: ₹' + discountInr + '\n';
            messageBody += 'Net Payable: ₹' + netPayableInr + '\n';
            messageBody += 'Status: ' + invoice.Payment_Status__c + '\n\n';
        }
        
        if (String.isNotBlank(report.Discharge_Advice__c)) {
            messageBody += '📝 *Discharge Advice:*\n' + report.Discharge_Advice__c + '\n\n';
        }
        
        messageBody += 'Thank you for choosing our hospital. Get well soon!';
        
        String recipientPhone = report.Patient__r.Phone__c;
        if (String.isBlank(recipientPhone)) {
            recipientPhone = '9910154408'; // fallback testing number
        }
        
        if (inAsyncJob && !Test.isRunningTest()) {
            System.enqueueJob(new FinalReportTwilioSendQueueable(recipientPhone, messageBody, null));
        } else {
            if (Test.isRunningTest()) {
                WhatsAppService.sendWhatsAppMessage(recipientPhone, messageBody);
            } else {
                WhatsAppService.sendWhatsAppMessageSync(recipientPhone, messageBody);
            }
        }
    }
}
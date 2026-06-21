public without sharing class FinalReportController {

    public class ReportWrapper {
        @AuraEnabled public Final_Report__c report { get; set; }
        @AuraEnabled public Patient__c patient { get; set; }
        @AuraEnabled public Admission__c admission { get; set; }
        @AuraEnabled public Appointment__c appointment { get; set; }
        @AuraEnabled public List<Lab_Result__c> labResults { get; set; }
        @AuraEnabled public List<Prescription__c> prescriptions { get; set; }
        @AuraEnabled public List<PrescriptionLineItemWrapper> prescriptionLineItems { get; set; }
        @AuraEnabled public List<Invoice_Line_Item__c> invoiceLineItems { get; set; }
        @AuraEnabled public Invoice__c invoice { get; set; }
    }

    public class PrescriptionLineItemWrapper {
        @AuraEnabled public String medicineName { get; set; }
        @AuraEnabled public String dosage { get; set; }
        @AuraEnabled public String frequency { get; set; }
        @AuraEnabled public Decimal durationDays { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal totalPrice { get; set; }
        @AuraEnabled public String instructions { get; set; }
        @AuraEnabled public String consumption { get; set; }
        @AuraEnabled public Boolean morning { get; set; }
        @AuraEnabled public Boolean afternoon { get; set; }
        @AuraEnabled public Boolean night { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static ReportWrapper getReportDetails(Id reportId) {
        ReportWrapper wrapper = new ReportWrapper();
        
        // 1. Fetch Final Report record
        Final_Report__c report = [
            SELECT Id, Name, Patient__c, Doctor__c, Admission__c, Appointment__c, Summary__c, Discharge_Advice__c, Status__c, Doctor__r.Name
            FROM Final_Report__c
            WHERE Id = :reportId
            LIMIT 1
        ];
        wrapper.report = report;
        
        // 2. Fetch Patient Details
        if (report.Patient__c != null) {
            wrapper.patient = [
                SELECT Id, Name, Phone__c, Email__c, Gender__c, Blood_Group__c, Aadhaar_Last_4__c, Address__c, Patient_ID__c
                FROM Patient__c
                WHERE Id = :report.Patient__c
                LIMIT 1
            ];
        }
        
        // 3. Fetch Appointment Details
        if (report.Appointment__c != null) {
            wrapper.appointment = [
                SELECT Id, Name, Appointment_Date__c, Appointment_Time__c, Symptoms__c, Doctor__r.Name, Department__r.Name
                FROM Appointment__c
                WHERE Id = :report.Appointment__c
                LIMIT 1
            ];
        }
        
        // 4. Fetch Admission & Discharge details
        if (report.Admission__c != null) {
            wrapper.admission = [
                SELECT Id, Name, Admission_Date_Time__c, Actual_Discharge_Date_Time__c, Diagnosis__c, Doctor__r.Name, Room__r.Name, Bed__r.Name
                FROM Admission__c
                WHERE Id = :report.Admission__c
                LIMIT 1
            ];
            
            // If appointment details were not linked directly, fetch them via the Admission relationship
            if (wrapper.appointment == null && wrapper.admission.Id != null) {
                List<Admission__c> linkedAdms = [SELECT Appointment__c FROM Admission__c WHERE Id = :report.Admission__c];
                if (!linkedAdms.isEmpty() && linkedAdms[0].Appointment__c != null) {
                    wrapper.appointment = [
                        SELECT Id, Name, Appointment_Date__c, Appointment_Time__c, Symptoms__c, Doctor__r.Name, Department__r.Name
                        FROM Appointment__c
                        WHERE Id = :linkedAdms[0].Appointment__c
                        LIMIT 1
                    ];
                }
            }
        }
        
        // 5. Fetch Lab Results (Only for current Admission)
        if (report.Admission__c != null) {
            wrapper.labResults = [
                SELECT Id, Lab_Test__r.Name, Result_Summary__c, Status__c, Doctor__r.Name
                FROM Lab_Result__c
                WHERE Admission__c = :report.Admission__c
            ];
        } else {
            wrapper.labResults = new List<Lab_Result__c>();
        }
        
        // 6. Fetch Prescriptions and Line Items (look up direct Admission + Medical Record linkages)
        Set<Id> prescriptionIds = new Set<Id>();
        if (report.Admission__c != null) {
            for (Prescription__c p : [SELECT Id FROM Prescription__c WHERE Admission__c = :report.Admission__c]) {
                prescriptionIds.add(p.Id);
            }
            for (Prescription__c p : [SELECT Id FROM Prescription__c WHERE Medical_Record__r.Admission__c = :report.Admission__c]) {
                prescriptionIds.add(p.Id);
            }
        }
        if (report.Appointment__c != null) {
            for (Prescription__c p : [SELECT Id FROM Prescription__c WHERE Medical_Record__r.Appointment__c = :report.Appointment__c]) {
                prescriptionIds.add(p.Id);
            }
        }

        wrapper.prescriptions = new List<Prescription__c>();
        wrapper.prescriptionLineItems = new List<PrescriptionLineItemWrapper>();

        if (!prescriptionIds.isEmpty()) {
            wrapper.prescriptions = [
                SELECT Id, Medicine__c, Medicine__r.Name, Instructions__c, Quantity__c, Unit_Price__c, Total_Medicine_Bill__c, Prescription_Date__c, Doctor__r.Name
                FROM Prescription__c
                WHERE Id IN :prescriptionIds
            ];
            
            // Query detailed line items
            List<Prescription_Line_Item__c> lines = [
                SELECT Prescription__c, Medicine__c, Medicine__r.Name, Dosage__c,
                       Frequency__c, Duration_Days__c, Quantity__c, Total_Price__c
                FROM Prescription_Line_Item__c
                WHERE Prescription__c IN :prescriptionIds
            ];
            
            Set<Id> prescriptionIdsWithLines = new Set<Id>();
            for (Prescription_Line_Item__c line : lines) {
                if (line.Medicine__c != null) {
                    PrescriptionLineItemWrapper w = new PrescriptionLineItemWrapper();
                    w.medicineName = line.Medicine__r.Name;
                    w.dosage = line.Dosage__c != null ? line.Dosage__c : 'N/A';
                    w.frequency = line.Frequency__c != null ? line.Frequency__c : 'N/A';
                    w.durationDays = line.Duration_Days__c != null ? line.Duration_Days__c : 0;
                    w.quantity = line.Quantity__c != null ? line.Quantity__c : 0;
                    w.totalPrice = line.Total_Price__c != null ? line.Total_Price__c : 0;
                    w.instructions = '';
                    w.consumption = '';
                    w.morning = false;
                    w.afternoon = false;
                    w.night = false;
                    wrapper.prescriptionLineItems.add(w);
                    prescriptionIdsWithLines.add(line.Prescription__c);
                }
            }

            // Also convert direct Prescription__c items (when Medicine__c is populated directly on header)
            for (Prescription__c pr : wrapper.prescriptions) {
                if (pr.Medicine__c != null && !prescriptionIdsWithLines.contains(pr.Id)) {
                    PrescriptionLineItemWrapper w = new PrescriptionLineItemWrapper();
                    w.medicineName = pr.Medicine__r.Name;
                    w.dosage = 'As prescribed';
                    w.frequency = 'As prescribed';
                    w.durationDays = 0;
                    w.quantity = pr.Quantity__c != null ? pr.Quantity__c : 0;
                    w.totalPrice = pr.Total_Medicine_Bill__c != null ? pr.Total_Medicine_Bill__c : 0;
                    w.instructions = pr.Instructions__c != null ? pr.Instructions__c : '';
                    w.consumption = '';
                    w.morning = false;
                    w.afternoon = false;
                    w.night = false;
                    wrapper.prescriptionLineItems.add(w);
                }
            }
        }
        
        // 7. Fetch Invoice & Invoice Line Items
        wrapper.invoiceLineItems = new List<Invoice_Line_Item__c>();
        if (report.Admission__c != null) {
            List<Invoice__c> invoices = [
                SELECT Id, Name, Gross_Amount__c, Insurance_Covered_Amount__c, Discount_Amount__c, Non_Billable_Deduction__c, Net_Amount__c, Net_Payable__c, Payment_Status__c
                FROM Invoice__c
                WHERE Admission__c = :report.Admission__c
                LIMIT 1
            ];
            if (!invoices.isEmpty()) {
                wrapper.invoice = invoices[0];
                wrapper.invoiceLineItems = [
                    SELECT Id, Charge_Type__c, Description__c, Quantity__c, Unit_Price__c, Line_Total__c
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__c = :wrapper.invoice.Id
                    AND Charge_Type__c NOT IN ('Insurance', 'Insurance Deduction')
                ];
            }
        }
        
        return wrapper;
    }

    @AuraEnabled
    public static void sendReportWhatsApp(Id reportId) {
        try {
            SendFinalReportWhatsApp.sendReport(reportId, true);
        } catch (Exception ex) {
            throw new AuraHandledException('Error sending report via WhatsApp: ' + ex.getMessage());
        }
    }
}
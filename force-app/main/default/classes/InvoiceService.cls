public with sharing class InvoiceService {
    public static Map<Id, Invoice__c> getOrCreateForAdmissions(List<Admission__c> admissions) {
        Map<Id, Invoice__c> invoiceByAdmission = new Map<Id, Invoice__c>();
        Map<Id, Admission__c> admissionById = new Map<Id, Admission__c>();

        for (Admission__c admission : admissions) {
            if (admission != null && admission.Id != null) {
                admissionById.put(admission.Id, admission);
            }
        }

        if (admissionById.isEmpty()) {
            return invoiceByAdmission;
        }

        for (Invoice__c invoice : [
            SELECT Id, Admission__c, Patient__c, Insurance_Covered_Amount__c, Discount_Amount__c
            FROM Invoice__c
            WHERE Admission__c IN :admissionById.keySet()
            ORDER BY CreatedDate ASC
        ]) {
            if (!invoiceByAdmission.containsKey(invoice.Admission__c)) {
                invoiceByAdmission.put(invoice.Admission__c, invoice);
            }
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        for (Admission__c admission : admissionById.values()) {
            if (invoiceByAdmission.containsKey(admission.Id) || admission.Patient__c == null) {
                continue;
            }

            Invoice__c invoice = new Invoice__c(
                Admission__c = admission.Id,
                Patient__c = admission.Patient__c,
                Patient_Category__c = admission.Patient__r == null ? null : admission.Patient__r.Patient_Category__c,
                Insurance_Covered_Amount__c = BillingUtil.zeroIfNull(admission.Insurance_Covered_Amount__c),
                Invoice_Date__c = Date.today(),
                Due_Date__c = Date.today().addDays(30),
                Status__c = 'Unpaid',
                Payment_Status__c = 'Unpaid'
            );
            invoicesToInsert.add(invoice);
            invoiceByAdmission.put(admission.Id, invoice);
        }

        if (!invoicesToInsert.isEmpty()) {
            insert invoicesToInsert;
        }

        return invoiceByAdmission;
    }

    public static Map<Id, Invoice__c> getOrCreateForPatients(Map<Id, Id> sourceToPatient) {
        Map<Id, Invoice__c> invoiceBySource = new Map<Id, Invoice__c>();
        Set<Id> patientIds = new Set<Id>();

        for (Id patientId : sourceToPatient.values()) {
            if (patientId != null) {
                patientIds.add(patientId);
            }
        }

        if (patientIds.isEmpty()) {
            return invoiceBySource;
        }

        Map<Id, Patient__c> patientsById = new Map<Id, Patient__c>([
            SELECT Id, Patient_Category__c
            FROM Patient__c
            WHERE Id IN :patientIds
        ]);

        Map<Id, Invoice__c> invoiceByPatient = new Map<Id, Invoice__c>();
        for (Invoice__c invoice : [
            SELECT Id, Patient__c, Insurance_Covered_Amount__c, Discount_Amount__c
            FROM Invoice__c
            WHERE Patient__c IN :patientIds
            AND Admission__c = null
            AND Invoice_Date__c = :Date.today()
            ORDER BY CreatedDate ASC
        ]) {
            if (!invoiceByPatient.containsKey(invoice.Patient__c)) {
                invoiceByPatient.put(invoice.Patient__c, invoice);
            }
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        for (Id patientId : patientIds) {
            if (!invoiceByPatient.containsKey(patientId)) {
                Invoice__c invoice = new Invoice__c(
                    Patient__c = patientId,
                    Patient_Category__c = patientsById.containsKey(patientId) ? patientsById.get(patientId).Patient_Category__c : null,
                    Invoice_Date__c = Date.today(),
                    Due_Date__c = Date.today().addDays(30),
                    Status__c = 'Unpaid',
                    Payment_Status__c = 'Unpaid'
                );
                invoicesToInsert.add(invoice);
                invoiceByPatient.put(patientId, invoice);
            }
        }

        if (!invoicesToInsert.isEmpty()) {
            insert invoicesToInsert;
        }

        for (Id sourceId : sourceToPatient.keySet()) {
            invoiceBySource.put(sourceId, invoiceByPatient.get(sourceToPatient.get(sourceId)));
        }

        return invoiceBySource;
    }

    public static void updateTotals(Set<Id> invoiceIds) {
        BillingCalculatorService.recalculate(invoiceIds);
    }
}
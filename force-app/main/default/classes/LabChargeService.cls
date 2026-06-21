public with sharing class LabChargeService {
    public static Set<Id> createCharges(Set<Id> labResultIds) {
        if (labResultIds == null || labResultIds.isEmpty()) {
            return new Set<Id>();
        }

        List<Lab_Result__c> labResults = [
            SELECT Id, Patient__c, Admission__c, Lab_Test__c,
                   Lab_Test__r.Name, Lab_Test__r.Standard_Rate__c
            FROM Lab_Result__c
            WHERE Id IN :labResultIds
            AND Status__c = 'Completed'
            AND Lab_Test__c != null
        ];

        Map<Id, Invoice__c> invoiceByLabResult = getInvoices(labResults);
        Map<Id, BillingCharge> chargeByLabResult = new Map<Id, BillingCharge>();

        for (Lab_Result__c labResult : labResults) {
            Decimal rate = labResult.Lab_Test__r == null ? 0 : BillingUtil.zeroIfNull(labResult.Lab_Test__r.Standard_Rate__c);
            if (rate <= 0) {
                continue;
            }

            chargeByLabResult.put(
                labResult.Id,
                new BillingCharge(BillingUtil.LAB, labResult.Id, 'Lab Test - ' + labResult.Lab_Test__r.Name, 1, rate)
            );
        }

        Set<Id> invoiceIds = InvoiceLineItemService.upsertCharges(invoiceByLabResult, chargeByLabResult);
        InvoiceService.updateTotals(invoiceIds);
        return invoiceIds;
    }

    private static Map<Id, Invoice__c> getInvoices(List<Lab_Result__c> labResults) {
        Map<Id, Invoice__c> invoiceByLabResult = new Map<Id, Invoice__c>();
        Map<Id, List<Lab_Result__c>> labsByAdmission = new Map<Id, List<Lab_Result__c>>();
        Map<Id, Id> sourceToPatient = new Map<Id, Id>();

        for (Lab_Result__c labResult : labResults) {
            if (labResult.Admission__c != null) {
                if (!labsByAdmission.containsKey(labResult.Admission__c)) {
                    labsByAdmission.put(labResult.Admission__c, new List<Lab_Result__c>());
                }
                labsByAdmission.get(labResult.Admission__c).add(labResult);
            } else if (labResult.Patient__c != null) {
                sourceToPatient.put(labResult.Id, labResult.Patient__c);
            }
        }

        if (!labsByAdmission.isEmpty()) {
            List<Admission__c> admissions = [
                SELECT Id, Patient__c, Patient__r.Patient_Category__c, Insurance_Covered_Amount__c
                FROM Admission__c
                WHERE Id IN :labsByAdmission.keySet()
            ];
            Map<Id, Invoice__c> invoiceByAdmission = InvoiceService.getOrCreateForAdmissions(admissions);
            for (Id admissionId : labsByAdmission.keySet()) {
                for (Lab_Result__c labResult : labsByAdmission.get(admissionId)) {
                    invoiceByLabResult.put(labResult.Id, invoiceByAdmission.get(admissionId));
                }
            }
        }

        invoiceByLabResult.putAll(InvoiceService.getOrCreateForPatients(sourceToPatient));
        return invoiceByLabResult;
    }
}
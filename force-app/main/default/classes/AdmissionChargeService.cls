public with sharing class AdmissionChargeService {
    private static final Decimal DEFAULT_ADMISSION_FEE = 500;

    public static Set<Id> createCharges(Set<Id> admissionIds) {
        if (admissionIds == null || admissionIds.isEmpty()) {
            return new Set<Id>();
        }

        List<Admission__c> admissions = [
            SELECT Id, Patient__c, Patient__r.Patient_Category__c, Insurance_Covered_Amount__c
            FROM Admission__c
            WHERE Id IN :admissionIds
        ];

        Map<Id, Invoice__c> invoiceByAdmission = InvoiceService.getOrCreateForAdmissions(admissions);
        Map<Id, BillingCharge> chargeByAdmission = new Map<Id, BillingCharge>();

        for (Admission__c admission : admissions) {
            chargeByAdmission.put(
                admission.Id,
                new BillingCharge(BillingUtil.ADMISSION, admission.Id, 'Admission Fee', 1, DEFAULT_ADMISSION_FEE)
            );
        }

        Set<Id> invoiceIds = InvoiceLineItemService.upsertCharges(invoiceByAdmission, chargeByAdmission);
        InvoiceService.updateTotals(invoiceIds);
        return invoiceIds;
    }
}
/**
 * HMS_InvoiceAuditHandler
 * ─────────────────────────────────────────────────────────────────────────────
 * Handles Invoice__c trigger events for audit logging.
 *
 * Fields confirmed in org inspection (Invoice__c):
 *   Admission__c (Lookup), Patient__c (Lookup), Status__c, Payment_Status__c,
 *   Gross_Amount__c, Net_Payable__c, Invoice_Date__c, Due_Date__c,
 *   Insurance_Policy__c (Lookup), Insurance_Verified__c (Checkbox),
 *   Patient_Category__c, Total_Amount__c, Net_Amount__c, Discount_Amount__c,
 *   Insurance_Covered_Amount__c, Insurance_Deduction__c, Non_Billable_Deduction__c
 *
 * Business rules:
 *   before insert: Warn (soft validation) if Insurance_Policy__c is populated
 *                  but Insurance_Verified__c is false.
 *   after insert:  Log BILL_GENERATED
 *   after update:  Log BILL_UPDATED
 * ─────────────────────────────────────────────────────────────────────────────
 */
public without sharing class HMS_InvoiceAuditHandler {

    // ─── Before Insert ────────────────────────────────────────────────────────
    public static void handleBeforeInsert(List<Invoice__c> invoices) {
        validateInsuranceStatus(invoices);
    }

    // ─── After Insert ─────────────────────────────────────────────────────────
    public static void handleAfterInsert(List<Invoice__c> invoices) {
        HMS_AuditLogService.log('Invoice__c', 'BILL_GENERATED', invoices, new List<SObject>());
    }

    // ─── After Update ─────────────────────────────────────────────────────────
    public static void handleAfterUpdate(List<Invoice__c> invoices,
                                         Map<Id, Invoice__c> oldMap) {
        List<SObject> newRecs = new List<SObject>();
        List<SObject> oldRecs = new List<SObject>();
        for (Invoice__c inv : invoices) {
            newRecs.add(inv);
            oldRecs.add(oldMap.get(inv.Id));
        }
        HMS_AuditLogService.log('Invoice__c', 'BILL_UPDATED', newRecs, oldRecs);
    }

    // ─── Insurance Validation ─────────────────────────────────────────────────
    /**
     * If an insurance policy is attached but not yet verified, add a hard error.
     * Hospitals must verify insurance before generating an invoice to ensure
     * coverage amounts are accurate.
     */
    private static void validateInsuranceStatus(List<Invoice__c> invoices) {
        for (Invoice__c inv : invoices) {
            if (inv.Insurance_Policy__c != null && inv.Insurance_Verified__c != true) {
                inv.addError(
                    'Insurance policy is attached but has not been verified. '
                    + 'Please verify insurance coverage before generating this invoice. '
                    + 'Contact the Insurance Desk to mark the policy as verified.'
                );
            }
        }
    }
}
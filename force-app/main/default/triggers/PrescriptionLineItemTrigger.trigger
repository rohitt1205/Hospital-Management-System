trigger PrescriptionLineItemTrigger on Prescription_Line_Item__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            InvoiceBillingService.handlePrescriptionLineItemsAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            InvoiceBillingService.handlePrescriptionLineItemsAfterUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }
}
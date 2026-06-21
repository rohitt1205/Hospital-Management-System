trigger LabResultTrigger on Lab_Result__c (after insert, after update) {
    if (Trigger.isInsert) {
        InvoiceBillingService.handleLabResultAfterInsert(Trigger.new);
    }
    if (Trigger.isUpdate) {
        InvoiceBillingService.handleLabResultAfterUpdate(Trigger.oldMap, Trigger.newMap);
    }
}
trigger PatientServiceTrigger on Patient_Service__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            InvoiceBillingService.handlePatientServicesAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            InvoiceBillingService.handlePatientServicesAfterUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }
}
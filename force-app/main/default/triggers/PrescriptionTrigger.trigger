trigger PrescriptionTrigger on Prescription__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        InvoiceBillingService.populatePrescriptionPricing(Trigger.new);
        if (Trigger.isUpdate) {
            StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Prescription__c', 'Status__c');
        }
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            InvoiceBillingService.handlePrescriptionsAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            InvoiceBillingService.handlePrescriptionsAfterUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }
}
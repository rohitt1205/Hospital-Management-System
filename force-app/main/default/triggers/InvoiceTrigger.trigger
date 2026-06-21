trigger InvoiceTrigger on Invoice__c (before insert, before update) {
    InvoiceAutomationHandler.beforeSave(Trigger.new, Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate);
    if (Trigger.isBefore && Trigger.isUpdate) {
        StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Invoice__c', 'Status__c');
        StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Invoice__c', 'Payment_Status__c');
    }
}
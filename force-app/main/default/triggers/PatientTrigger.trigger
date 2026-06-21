trigger PatientTrigger on Patient__c (before update, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Patient__c', 'Patient_Approval_Status__c');
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        PatientTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
trigger DischargeTrigger on Discharge__c (before update) {
    StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Discharge__c', 'Status__c');
}
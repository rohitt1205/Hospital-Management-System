trigger PaymentTrigger on Payment__c (before update) {
    StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Payment__c', 'Status__c');
}
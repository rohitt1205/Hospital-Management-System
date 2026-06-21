trigger InsurancePolicyTrigger on Insurance_Policy__c (before update) {
    StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Insurance_Policy__c', 'Verification_Status__c');
}
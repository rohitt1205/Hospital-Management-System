trigger DonationTrigger on Donation__c (before update) {
    StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Donation__c', 'Status__c');
}
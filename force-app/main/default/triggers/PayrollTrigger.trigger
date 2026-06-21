trigger PayrollTrigger on Payroll__c (before update) {
    StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Payroll__c', 'Status__c');
}
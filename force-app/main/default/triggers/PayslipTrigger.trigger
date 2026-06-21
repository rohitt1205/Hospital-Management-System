trigger PayslipTrigger on Payslip__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            PayslipTriggerHandler.validatePayslips(Trigger.new);
        }
        if (Trigger.isUpdate) {
            StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Payslip__c', 'Status__c');
        }
    }
}
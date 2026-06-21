trigger FinalReportTrigger on Final_Report__c (before insert, before update) {
    if (Trigger.isBefore) {
        FinalReportAutomationHandler.handleFinalReportBeforeSave(Trigger.new);
        FinalReportAutomationHandler.validateUniqueAdmission(Trigger.new, Trigger.oldMap);
        if (Trigger.isUpdate) {
            StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Final_Report__c', 'Status__c');
        }
    }
}
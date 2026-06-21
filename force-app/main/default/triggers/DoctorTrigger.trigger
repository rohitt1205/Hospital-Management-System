trigger DoctorTrigger on Doctor__c (before insert, before update) {
    DoctorAutomationHandler.beforeSave(Trigger.new, Trigger.isInsert);
}
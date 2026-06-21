trigger GuardianTrigger on Guardian__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            GuardianTriggerHandler.validatePrimaryGuardians(Trigger.new, null);
        } else if (Trigger.isUpdate) {
            GuardianTriggerHandler.validatePrimaryGuardians(Trigger.new, Trigger.oldMap);
        }
    }
}
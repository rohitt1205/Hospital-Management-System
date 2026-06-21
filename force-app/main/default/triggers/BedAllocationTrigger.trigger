trigger BedAllocationTrigger on Bed_Allocation__c (
    before insert,
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    if (Trigger.isBefore) {
        FacilityAutomationHandler.beforeBedAllocationSave(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
    }
    if (Trigger.isAfter) {
        FacilityAutomationHandler.afterBedAllocationChange(
            Trigger.isDelete ? null : Trigger.new,
            Trigger.isInsert || Trigger.isUndelete ? null : Trigger.old
        );
        if (!Trigger.isDelete) {
            HMSNotificationService.enqueueWardManagerBedNotificationsFromChange(
                Trigger.new,
                Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap
            );
        }
    }
}
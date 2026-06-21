trigger PatientPortalUserTrigger on Patient__c (after insert, after update) {
    PatientPortalLinkService.enforceUniquePortalUser(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
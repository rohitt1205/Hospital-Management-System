trigger UserTrigger on User (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        PatientPortalProvisioner.handleNewUsers(Trigger.new);
    }
}
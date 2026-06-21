/**
 * HMS_PatientTrigger
 * Delegates all Patient__c trigger logic to HMS_PatientAuditHandler.
 * NOTE: Existing PatientAdmissionHandler is NOT replaced — it handles different events
 * (admission-side patient creation). This trigger handles Patient__c directly.
 */
trigger HMS_PatientTrigger on Patient__c (before insert, after insert, after update, before delete) {
    if (Trigger.isBefore && Trigger.isInsert) {
        HMS_PatientAuditHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        HMS_PatientAuditHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        HMS_PatientAuditHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isBefore && Trigger.isDelete) {
        HMS_PatientAuditHandler.handleBeforeDelete(Trigger.old);
    }
}
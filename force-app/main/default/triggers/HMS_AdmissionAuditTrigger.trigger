/**
 * HMS_AdmissionAuditTrigger
 * Adds audit logging layer to Admission__c without modifying the existing
 * AdmissionTrigger/PatientAdmissionHandler which handles patient creation logic.
 *
 * NOTE: The existing AdmissionTrigger handles before insert/update + after insert/update.
 * This trigger adds the before delete context and audit events to all existing contexts.
 * Salesforce allows multiple triggers on the same object — order is not guaranteed
 * but both will execute. No conflicts exist since they handle different concerns.
 */
trigger HMS_AdmissionAuditTrigger on Admission__c (before insert, before update, after insert, after update, before delete) {
    if (Trigger.isBefore && Trigger.isInsert) {
        HMS_AdmissionAuditHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        HMS_AdmissionAuditHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        HMS_AdmissionAuditHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        HMS_AdmissionAuditHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isBefore && Trigger.isDelete) {
        HMS_AdmissionAuditHandler.handleBeforeDelete(Trigger.old);
    }
}
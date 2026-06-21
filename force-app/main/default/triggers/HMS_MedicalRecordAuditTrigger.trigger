/**
 * HMS_MedicalRecordAuditTrigger
 * Extends Medical_Record__c with audit logging and access control.
 * Co-exists with existing MedicalRecordTrigger (before insert/update via MedicalRecordService).
 * This trigger adds after insert, after update, and the additional before update check.
 *
 * NOTE: Both before update handlers will run. MedicalRecordService runs first (Resident logic).
 * HMS_MedicalRecordAuditHandler then adds the broader Doctor/Admin check.
 */
trigger HMS_MedicalRecordAuditTrigger on Medical_Record__c (before update, after insert, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        HMS_MedicalRecordAuditHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        HMS_MedicalRecordAuditHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        HMS_MedicalRecordAuditHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
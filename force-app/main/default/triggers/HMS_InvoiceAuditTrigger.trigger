/**
 * HMS_InvoiceAuditTrigger
 * Adds audit logging to Invoice__c. Co-exists with existing InvoiceTrigger
 * (which handles InvoiceAutomationHandler.beforeSave / discount calculation).
 * Covers after insert and after update contexts not present in the existing trigger.
 */
trigger HMS_InvoiceAuditTrigger on Invoice__c (before insert, after insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        HMS_InvoiceAuditHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        HMS_InvoiceAuditHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        HMS_InvoiceAuditHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
/**
 * HMS_AuditEventTrigger
 * Consumes HMS_Audit_Event__e Platform Events after they are published.
 * Enqueues HMS_DatadogCalloutQueueable — callouts cannot run directly from this trigger.
 */
trigger HMS_AuditEventTrigger on HMS_Audit_Event__e (after insert) {
    System.enqueueJob(new HMS_DatadogCalloutQueueable(Trigger.new));
}
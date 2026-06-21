trigger AppointmentTrigger on Appointment__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            AppointmentAutomationHandler.beforeSave(
                Trigger.new,
                Trigger.isUpdate ? Trigger.oldMap : null
            );
        }
        if (Trigger.isUpdate) {
            StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Appointment__c', 'Status__c');
        }
    } else if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AppointmentAdmissionHandler.handleAfterInsert(Trigger.new);
            FinalReportAutomationHandler.handleAppointmentInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AppointmentAdmissionHandler.handleAfterUpdate(Trigger.oldMap, Trigger.new);
            InvoiceBillingService.handleAppointmentAfterUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }
}
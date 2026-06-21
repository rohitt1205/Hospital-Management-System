trigger AdmissionTrigger on Admission__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            PatientAdmissionHandler.handleBeforeInsert(Trigger.new);
            PatientAdmissionHandler.applyLifecycleBeforeSave(Trigger.new, (Map<Id, Admission__c>)null);
            EmergencyAdmissionSlaService.applyBeforeSave(Trigger.new, (Map<Id, Admission__c>)null);
        }
        if (Trigger.isUpdate) {
            PatientAdmissionHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
            PatientAdmissionHandler.applyLifecycleBeforeSave(Trigger.new, Trigger.oldMap);
            EmergencyAdmissionSlaService.applyBeforeSave(Trigger.new, Trigger.oldMap);
        }
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            PatientAdmissionHandler.handleAfterInsert(Trigger.new);
            InvoiceBillingService.handleAdmissionAfterInsert(Trigger.new);
            FinalReportAutomationHandler.handleAdmissionInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            PatientAdmissionHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
            InvoiceBillingService.handleAdmissionAfterUpdate(Trigger.oldMap, Trigger.newMap);
            
            List<Admission__c> modifiedAdmissions = new List<Admission__c>();
            for (Admission__c adm : Trigger.new) {
                Admission__c oldAdm = Trigger.oldMap.get(adm.Id);
                if (adm.Appointment__c != oldAdm.Appointment__c || adm.Patient__c != oldAdm.Patient__c || adm.Doctor__c != oldAdm.Doctor__c) {
                    modifiedAdmissions.add(adm);
                }
            }
            if (!modifiedAdmissions.isEmpty()) {
                FinalReportAutomationHandler.handleAdmissionInsert(modifiedAdmissions);
            }
        }
    }
}
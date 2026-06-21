trigger MedicalRecordTrigger on Medical_Record__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            MedicalRecordService.validateMedicalRecords(Trigger.new, null);
        } else if (Trigger.isUpdate) {
            MedicalRecordService.validateMedicalRecords(Trigger.new, Trigger.oldMap);
            StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Medical_Record__c', 'Record_Status__c');
        }
    }
}
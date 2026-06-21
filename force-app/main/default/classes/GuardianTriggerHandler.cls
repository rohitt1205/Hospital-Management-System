public with sharing class GuardianTriggerHandler {
    public static void validatePrimaryGuardians(List<Guardian__c> newGuardians, Map<Id, Guardian__c> oldMap) {
        Set<Id> patientIds = new Set<Id>();
        List<Guardian__c> primaryGuardiansToValidate = new List<Guardian__c>();
        
        Set<Id> patientsWithPrimaryInContext = new Set<Id>();
        
        for (Guardian__c g : newGuardians) {
            Boolean isPrimary = g.Primary_Guardian__c;
            Boolean wasPrimary = oldMap != null && oldMap.containsKey(g.Id) ? oldMap.get(g.Id).Primary_Guardian__c : false;
            
            if (isPrimary && (oldMap == null || !wasPrimary)) {
                if (g.Patient__c != null) {
                    if (patientsWithPrimaryInContext.contains(g.Patient__c)) {
                        g.addError('Only one primary guardian is allowed per patient.');
                    } else {
                        patientsWithPrimaryInContext.add(g.Patient__c);
                        patientIds.add(g.Patient__c);
                        primaryGuardiansToValidate.add(g);
                    }
                }
            }
        }
        
        if (patientIds.isEmpty()) return;
        
        Map<Id, Guardian__c> existingPrimaryGuardians = new Map<Id, Guardian__c>();
        for (Guardian__c g : [
            SELECT Id, Patient__c 
            FROM Guardian__c 
            WHERE Patient__c IN :patientIds AND Primary_Guardian__c = true
        ]) {
            existingPrimaryGuardians.put(g.Patient__c, g);
        }
        
        for (Guardian__c g : primaryGuardiansToValidate) {
            if (existingPrimaryGuardians.containsKey(g.Patient__c)) {
                Guardian__c existing = existingPrimaryGuardians.get(g.Patient__c);
                if (existing.Id != g.Id) {
                    g.addError('Only one primary guardian is allowed per patient.');
                }
            }
        }
    }
}
public with sharing class MedicalRecordService {

    public static void validateMedicalRecords(List<Medical_Record__c> newList, Map<Id, Medical_Record__c> oldMap) {
        // 1. Resolve current logged-in user's Doctor record
        Id currentUserId = UserInfo.getUserId();
        List<Doctor__c> currentDocs = [
            SELECT Id, Name, Staff__r.Staff_Role__c
            FROM Doctor__c
            WHERE Staff__r.Salesforce_User__c = :currentUserId
            LIMIT 1
        ];
        Doctor__c currentDoc = currentDocs.isEmpty() ? null : currentDocs[0];

        // 2. Gather all doctor IDs of the records to query supervisor and role details
        Set<Id> doctorIds = new Set<Id>();
        for (Medical_Record__c mr : newList) {
            // Default Doctor__c to current user's doctor if null
            if (mr.Doctor__c == null && currentDoc != null) {
                mr.Doctor__c = currentDoc.Id;
            }
            if (mr.Doctor__c != null) {
                doctorIds.add(mr.Doctor__c);
            }
        }

        // Fetch doctors with their staff roles and supervisors
        Map<Id, Doctor__c> doctorMap = new Map<Id, Doctor__c>();
        if (!doctorIds.isEmpty()) {
            doctorMap = new Map<Id, Doctor__c>([
                SELECT Id, Name, Supervisor__c, Supervisor__r.Name, Staff__r.Staff_Role__c
                FROM Doctor__c
                WHERE Id IN :doctorIds
            ]);
        }

        // 3. Perform validation checks
        for (Medical_Record__c mr : newList) {
            Medical_Record__c oldMr = oldMap != null ? oldMap.get(mr.Id) : null;
            Doctor__c creatorDoc = mr.Doctor__c != null ? doctorMap.get(mr.Doctor__c) : null;

            if (creatorDoc == null) continue;

            Boolean isResident = (creatorDoc.Staff__r.Staff_Role__c == 'Resident');

            if (isResident) {
                if (oldMr == null) {
                    // Scenario: Creating new record
                    if (mr.Record_Status__c == 'Final') {
                        mr.addError('Resident doctors cannot create medical records directly in Final status. Please submit for approval.');
                    }
                } else {
                    // Scenario: Updating existing record
                    
                    // If record was already Final, prevent any modification
                    if (oldMr.Record_Status__c == 'Final') {
                        mr.addError('This medical record has already been finalized and cannot be modified.');
                        continue;
                    }

                    // If status is changing to Final (Approve action)
                    if (mr.Record_Status__c == 'Final' && oldMr.Record_Status__c != 'Final') {
                        if (creatorDoc.Supervisor__c == null) {
                            mr.addError('No supervisor configured for resident ' + creatorDoc.Name + '. Cannot approve.');
                        } else if (currentDoc == null || currentDoc.Id != creatorDoc.Supervisor__c) {
                            String supervisorName = creatorDoc.Supervisor__r.Name != null ? creatorDoc.Supervisor__r.Name : 'their supervisor';
                            mr.addError('Only the supervisor doctor (' + supervisorName + ') can approve this record.');
                        }
                    }
                }
            } else {
                // For non-residents (Senior Doctors), prevent editing record once it is finalized
                if (oldMr != null && oldMr.Record_Status__c == 'Final') {
                    mr.addError('This medical record has already been finalized and cannot be modified.');
                }
            }
        }
    }
}
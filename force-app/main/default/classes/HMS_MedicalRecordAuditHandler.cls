/**
 * HMS_MedicalRecordAuditHandler
 * ─────────────────────────────────────────────────────────────────────────────
 * Extends Medical_Record__c with audit logging for Datadog.
 *
 * Fields confirmed in org inspection (Medical_Record__c):
 *   Doctor__c (Lookup→Doctor__c), Patient__c (Lookup→Patient__c),
 *   Admission__c (Lookup→Admission__c), Appointment__c (Lookup→Appointment__c),
 *   Clinical_Notes__c (Text), Diagnosis_Summary__c (Text), Record_Status__c (Picklist)
 *
 * Business rules:
 *   before update: Authorization check is already handled by MedicalRecordService
 *                  (validates Resident vs Supervisor access). This handler extends it
 *                  with explicit profile/permission checks for System Admin.
 *   after insert:  Log MEDICAL_RECORD_CREATED
 *   after update:  Log MEDICAL_RECORD_CHANGED
 * ─────────────────────────────────────────────────────────────────────────────
 */
public without sharing class HMS_MedicalRecordAuditHandler {

    // ─── Before Update ────────────────────────────────────────────────────────
    /**
     * Validates that the running user is either:
     *   (a) The assigned Doctor (matched via Doctor__c → Staff__r.Salesforce_User__c)
     *   (b) A System Administrator profile
     *   (c) Has the HMS_Admin permission set
     * MedicalRecordService already validates Resident/Supervisor logic — this adds
     * the broader permission check so non-doctors cannot edit medical records.
     */
    public static void handleBeforeUpdate(List<Medical_Record__c> newRecords,
                                          Map<Id, Medical_Record__c> oldMap) {
        // Get current user profile to check for sysadmin bypass
        Id currentUserId = UserInfo.getUserId();
        String currentProfileName = [
            SELECT Profile.Name FROM User WHERE Id = :currentUserId LIMIT 1
        ].Profile.Name;

        // Sysadmin bypass
        if (currentProfileName == 'System Administrator') {
            return;
        }

        // Check if user has HMS_Admin permission set
        List<PermissionSetAssignment> psaList = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :currentUserId
            AND   PermissionSet.Name IN ('HMS_Admin', 'HMS_Audit_Logger')
            LIMIT 1
        ];
        if (!psaList.isEmpty()) {
            return;
        }

        // Collect Doctor IDs on records being updated
        Set<Id> doctorIds = new Set<Id>();
        for (Medical_Record__c mr : newRecords) {
            if (mr.Doctor__c != null) {
                doctorIds.add(mr.Doctor__c);
            }
        }

        // Map Doctor → Salesforce_User__c
        Map<Id, Doctor__c> doctorMap = new Map<Id, Doctor__c>();
        if (!doctorIds.isEmpty()) {
            doctorMap = new Map<Id, Doctor__c>([
                SELECT Id, Staff__r.Salesforce_User__c
                FROM   Doctor__c
                WHERE  Id IN :doctorIds
            ]);
        }

        for (Medical_Record__c mr : newRecords) {
            if (mr.Doctor__c == null) {
                mr.addError('Cannot edit Medical Record: no assigned Doctor on this record.');
                continue;
            }
            Doctor__c assignedDoc = doctorMap.get(mr.Doctor__c);
            if (assignedDoc == null) {
                mr.addError('Cannot verify assigned doctor. Access denied.');
                continue;
            }
            Id assignedUserId = assignedDoc.Staff__r.Salesforce_User__c;
            if (assignedUserId == null || assignedUserId != currentUserId) {
                mr.addError(
                    'Access Denied: Only the assigned doctor or a System Administrator '
                    + 'may edit this Medical Record.'
                );
            }
        }
    }

    // ─── After Insert ─────────────────────────────────────────────────────────
    public static void handleAfterInsert(List<Medical_Record__c> newRecords) {
        HMS_AuditLogService.log('Medical_Record__c', 'MEDICAL_RECORD_CREATED',
            newRecords, new List<SObject>());
    }

    // ─── After Update ─────────────────────────────────────────────────────────
    public static void handleAfterUpdate(List<Medical_Record__c> newRecords,
                                         Map<Id, Medical_Record__c> oldMap) {
        List<SObject> newRecs = new List<SObject>();
        List<SObject> oldRecs = new List<SObject>();
        for (Medical_Record__c mr : newRecords) {
            newRecs.add(mr);
            oldRecs.add(oldMap.get(mr.Id));
        }
        HMS_AuditLogService.log('Medical_Record__c', 'MEDICAL_RECORD_CHANGED', newRecs, oldRecs);
    }
}
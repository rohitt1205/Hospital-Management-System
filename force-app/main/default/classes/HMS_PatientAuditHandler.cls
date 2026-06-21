/**
 * HMS_PatientAuditHandler
 * ─────────────────────────────────────────────────────────────────────────────
 * Handles Patient__c trigger events for audit logging and business validations.
 *
 * Fields confirmed in org inspection:
 *   Patient__c: Date_of_Birth__c (Date), Guardian__c (Lookup→Guardian__c),
 *   Name, Phone__c, Email__c, Gender__c, Blood_Group__c, Status__c,
 *   Patient_Category__c, Age__c, Address__c, Aadhaar_Last_4__c, Portal_User__c,
 *   Patient_Approval_Status__c, Patient_ID__c
 *
 * Business rules:
 *   before insert: If patient is a minor (DOB within 18 years), Guardian__c must be populated.
 *   after insert:  Log PATIENT_REGISTERED
 *   after update:  Log PATIENT_UPDATED (changed fields)
 *   before delete: Log PATIENT_DELETED
 * ─────────────────────────────────────────────────────────────────────────────
 */
public without sharing class HMS_PatientAuditHandler {

    private static final Integer MINOR_AGE_THRESHOLD = 18;

    // ─── Before Insert ────────────────────────────────────────────────────────
    public static void handleBeforeInsert(List<Patient__c> newPatients) {
        validateMinorGuardian(newPatients);
    }

    // ─── After Insert ─────────────────────────────────────────────────────────
    public static void handleAfterInsert(List<Patient__c> newPatients) {
        HMS_AuditLogService.log('Patient__c', 'PATIENT_REGISTERED', newPatients, new List<SObject>());
    }

    // ─── After Update ─────────────────────────────────────────────────────────
    public static void handleAfterUpdate(List<Patient__c> newPatients,
                                         Map<Id, Patient__c> oldMap) {
        List<SObject> newRecs = new List<SObject>();
        List<SObject> oldRecs = new List<SObject>();
        for (Patient__c p : newPatients) {
            newRecs.add(p);
            oldRecs.add(oldMap.get(p.Id));
        }
        HMS_AuditLogService.log('Patient__c', 'PATIENT_UPDATED', newRecs, oldRecs);
    }

    // ─── Before Delete ────────────────────────────────────────────────────────
    public static void handleBeforeDelete(List<Patient__c> oldPatients) {
        HMS_AuditLogService.log('Patient__c', 'PATIENT_DELETED', new List<SObject>(), oldPatients);
    }

    // ─── Validation: Minor requires Guardian ──────────────────────────────────
    private static void validateMinorGuardian(List<Patient__c> patients) {
        Date today = Date.today();
        for (Patient__c p : patients) {
            if (p.Date_of_Birth__c == null) {
                continue; // Cannot determine age, skip validation
            }
            Integer age = p.Date_of_Birth__c.daysBetween(today) / 365;
            if (age < MINOR_AGE_THRESHOLD && p.Guardian__c == null) {
                p.addError(
                    'A Guardian is required for patients under 18 years of age. '
                    + 'Please assign a Guardian before saving.'
                );
            }
        }
    }
}
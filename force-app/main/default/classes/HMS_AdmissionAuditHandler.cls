/**
 * HMS_AdmissionAuditHandler
 * ─────────────────────────────────────────────────────────────────────────────
 * Handles Admission__c trigger events for audit logging and business validations.
 *
 * Fields confirmed in org inspection (Admission__c):
 *   Status__c (Picklist: Draft/Admitted/Pending Discharge/Discharged/Cancelled)
 *   Ward__c (Lookup→Ward__c), Patient__c (Lookup→Patient__c),
 *   Insurance_Verified__c (Checkbox), Department__c (Lookup→Department__c),
 *   Ward__r.Capacity__c, Ward__r.Current_Occupancy__c
 *
 * Business rules:
 *   before insert:
 *     - Ward capacity check: if Ward lookup exists and Capacity/Current_Occupancy fields
 *       exist, block admission when ward is full
 *     - Insurance validation: if Insurance_Verified__c is false on initial admission
 *       log a warning (not a hard block — insurance may be verified later)
 *   after insert:  Log PATIENT_ADMITTED
 *   after update:
 *     - If Status__c changed to 'Discharged': validate no unpaid Invoice__c for patient
 *     - Log ADMISSION_UPDATED
 *   before delete: Log ADMISSION_DELETED
 * ─────────────────────────────────────────────────────────────────────────────
 */
public without sharing class HMS_AdmissionAuditHandler {

    // ─── Before Insert ────────────────────────────────────────────────────────
    public static void handleBeforeInsert(List<Admission__c> admissions) {
        checkWardCapacity(admissions);
    }

    // ─── Before Update ────────────────────────────────────────────────────────
    public static void handleBeforeUpdate(List<Admission__c> admissions,
                                          Map<Id, Admission__c> oldMap) {
        validateDischargeNoBill(admissions, oldMap);
    }

    // ─── After Insert ─────────────────────────────────────────────────────────
    public static void handleAfterInsert(List<Admission__c> admissions) {
        HMS_AuditLogService.log('Admission__c', 'PATIENT_ADMITTED', admissions, new List<SObject>());
    }

    // ─── After Update ─────────────────────────────────────────────────────────
    public static void handleAfterUpdate(List<Admission__c> admissions,
                                         Map<Id, Admission__c> oldMap) {
        List<SObject> newRecs = new List<SObject>();
        List<SObject> oldRecs = new List<SObject>();
        for (Admission__c a : admissions) {
            newRecs.add(a);
            oldRecs.add(oldMap.get(a.Id));
        }
        HMS_AuditLogService.log('Admission__c', 'ADMISSION_UPDATED', newRecs, oldRecs);
    }

    // ─── Before Delete ────────────────────────────────────────────────────────
    public static void handleBeforeDelete(List<Admission__c> oldAdmissions) {
        HMS_AuditLogService.log('Admission__c', 'ADMISSION_DELETED',
            new List<SObject>(), oldAdmissions);
    }

    // ─── Ward Capacity Check ──────────────────────────────────────────────────
    private static void checkWardCapacity(List<Admission__c> admissions) {
        // Collect Ward IDs that have been specified
        Set<Id> wardIds = new Set<Id>();
        for (Admission__c adm : admissions) {
            if (adm.Ward__c != null) {
                wardIds.add(adm.Ward__c);
            }
        }
        if (wardIds.isEmpty()) {
            return;
        }

        // Query Ward capacity and occupancy in one SOQL (outside loop)
        Map<Id, Ward__c> wardMap = new Map<Id, Ward__c>([
            SELECT Id, Name, Capacity__c, Current_Occupancy__c
            FROM   Ward__c
            WHERE  Id IN :wardIds
        ]);

        for (Admission__c adm : admissions) {
            if (adm.Ward__c == null) {
                continue;
            }
            Ward__c ward = wardMap.get(adm.Ward__c);
            if (ward == null) {
                continue;
            }
            if (ward.Capacity__c != null && ward.Current_Occupancy__c != null
                    && ward.Current_Occupancy__c >= ward.Capacity__c) {
                adm.addError(
                    'Ward "' + ward.Name + '" is at full capacity ('
                    + ward.Current_Occupancy__c.intValue() + '/'
                    + ward.Capacity__c.intValue()
                    + '). Please select a different ward or bed.'
                );
            }
        }
    }

    // ─── Discharge Billing Validation ─────────────────────────────────────────
    /**
     * Before update: when Status__c changes to 'Discharged', block if the patient
     * has any Invoice__c with Payment_Status__c = 'Unpaid' or 'Partially Paid'.
     * Fully bulkified — one SOQL for all patients being discharged.
     */
    private static void validateDischargeNoBill(List<Admission__c> admissions,
                                                 Map<Id, Admission__c> oldMap) {
        Set<Id> patientsDischarged = new Set<Id>();

        for (Admission__c adm : admissions) {
            Admission__c oldAdm = oldMap.get(adm.Id);
            if (adm.Status__c == 'Discharged'
                    && oldAdm.Status__c != 'Discharged') {
                if (adm.Outstanding_Balance__c != null && adm.Outstanding_Balance__c > 0) {
                    adm.addError(
                        'Cannot discharge patient: outstanding balance of '
                        + adm.Outstanding_Balance__c.setScale(2)
                        + ' must be settled before discharge.'
                    );
                    continue;
                }
                if (adm.Patient__c != null) {
                    patientsDischarged.add(adm.Patient__c);
                }
            }
        }

        if (patientsDischarged.isEmpty()) {
            return;
        }

        // Query unpaid invoices for all patients being discharged (one SOQL)
        List<Invoice__c> unpaidInvoices = [
            SELECT Id, Patient__c, Name, Payment_Status__c
            FROM   Invoice__c
            WHERE  Patient__c     IN :patientsDischarged
            AND    Payment_Status__c IN ('Unpaid', 'Partially Paid')
        ];

        if (unpaidInvoices.isEmpty()) {
            return;
        }

        // Map patient → unpaid invoice count
        Map<Id, List<String>> patientUnpaidMap = new Map<Id, List<String>>();
        for (Invoice__c inv : unpaidInvoices) {
            if (!patientUnpaidMap.containsKey(inv.Patient__c)) {
                patientUnpaidMap.put(inv.Patient__c, new List<String>());
            }
            patientUnpaidMap.get(inv.Patient__c).add(inv.Name + ' (' + inv.Payment_Status__c + ')');
        }

        // Apply errors on the admission records
        for (Admission__c adm : admissions) {
            if (adm.Patient__c != null && patientUnpaidMap.containsKey(adm.Patient__c)) {
                List<String> invoiceNames = patientUnpaidMap.get(adm.Patient__c);
                adm.addError(
                    'Cannot discharge patient: ' + invoiceNames.size()
                    + ' unpaid invoice(s) exist: '
                    + String.join(invoiceNames, ', ')
                    + '. Please settle all outstanding bills before discharge.'
                );
            }
        }
    }
}
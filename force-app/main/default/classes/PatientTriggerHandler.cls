public without sharing class PatientTriggerHandler {
    // Static recursion guard to prevent trigger loops between Patient and Admission updates
    public static Boolean isSyncing = false;

    public static void handleAfterUpdate(List<Patient__c> newPatients, Map<Id, Patient__c> oldMap) {
        if (isSyncing) {
            return;
        }

        Map<Id, String> patientIdToNewStatus = new Map<Id, String>();
        for (Patient__c patient : newPatients) {
            Patient__c oldPatient = oldMap.get(patient.Id);
            if (patient.Status__c != oldPatient.Status__c && patient.Status__c != null) {
                patientIdToNewStatus.put(patient.Id, patient.Status__c);
            }
        }

        if (patientIdToNewStatus.isEmpty()) {
            return;
        }

        // Find active Admission records for these patients
        // An admission is active if Status is not Discharged or Cancelled
        List<Admission__c> activeAdmissions = [
            SELECT Id, Patient__c, Status__c
            FROM Admission__c
            WHERE Patient__c IN :patientIdToNewStatus.keySet()
            AND Status__c NOT IN ('Discharged', 'Cancelled')
        ];

        if (activeAdmissions.isEmpty()) {
            return;
        }

        List<Admission__c> admissionsToUpdate = new List<Admission__c>();
        for (Admission__c admission : activeAdmissions) {
            String newPatientStatus = patientIdToNewStatus.get(admission.Patient__c);
            
            // Map Patient status back to Admission status
            String targetAdmissionStatus = null;
            if (newPatientStatus == 'Discharged') {
                targetAdmissionStatus = 'Discharged';
            } else if (newPatientStatus == 'Admitted') {
                targetAdmissionStatus = 'Admitted';
            }

            if (targetAdmissionStatus != null && admission.Status__c != targetAdmissionStatus) {
                // Prevent violating StatusTransitionValidator rules by checking allowed status sequence
                Boolean isAllowed = false;
                if (admission.Status__c == 'Draft') {
                    isAllowed = true;
                } else if (admission.Status__c == 'Admitted' && (targetAdmissionStatus == 'Pending Discharge' || targetAdmissionStatus == 'Discharged' || targetAdmissionStatus == 'Cancelled')) {
                    isAllowed = true;
                } else if (admission.Status__c == 'Pending Discharge' && (targetAdmissionStatus == 'Discharged' || targetAdmissionStatus == 'Cancelled')) {
                    isAllowed = true;
                }

                if (isAllowed) {
                    admission.Status__c = targetAdmissionStatus;
                    admissionsToUpdate.add(admission);
                }
            }
        }

        if (!admissionsToUpdate.isEmpty()) {
            isSyncing = true;
            try {
                update admissionsToUpdate;
            } finally {
                isSyncing = false;
            }
        }
    }
}
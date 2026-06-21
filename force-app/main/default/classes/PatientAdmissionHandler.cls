public without sharing class PatientAdmissionHandler {
    public static void applyLifecycleBeforeSave(List<Admission__c> admissions, Map<Id, Admission__c> oldMap) {
        for (Admission__c admission : admissions) {
            Admission__c oldAdmission = oldMap == null ? null : oldMap.get(admission.Id);
            if (admission.Status__c == 'Discharged'
                && (oldAdmission == null || oldAdmission.Status__c != 'Discharged')
                && admission.Actual_Discharge_Date_Time__c == null) {
                admission.Actual_Discharge_Date_Time__c = System.now();
            }
        }
        validateSingleActiveAdmission(admissions, oldMap);
    }

    private static void validateSingleActiveAdmission(List<Admission__c> admissions, Map<Id, Admission__c> oldMap) {
        Set<Id> patientIds = new Set<Id>();
        Set<Id> admissionIds = new Set<Id>();
        List<Admission__c> candidates = new List<Admission__c>();
        for (Admission__c admission : admissions) {
            if (admission.Id != null) admissionIds.add(admission.Id);
            if (admission.Patient__c == null || !isActiveAdmission(admission.Status__c)) continue;
            Admission__c oldAdmission = oldMap == null ? null : oldMap.get(admission.Id);
            if (oldAdmission == null || oldAdmission.Patient__c != admission.Patient__c
                || !isActiveAdmission(oldAdmission.Status__c)) {
                candidates.add(admission);
                patientIds.add(admission.Patient__c);
            }
        }
        if (candidates.isEmpty()) return;

        Map<Id, Admission__c> activeAdmissionByPatient = new Map<Id, Admission__c>();
        for (Admission__c existing : [
            SELECT Id, Name, Patient__c, Status__c FROM Admission__c
            WHERE Patient__c IN :patientIds
            AND Status__c NOT IN ('Discharged', 'Cancelled')
            AND Id NOT IN :admissionIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!activeAdmissionByPatient.containsKey(existing.Patient__c)) {
                activeAdmissionByPatient.put(existing.Patient__c, existing);
            }
        }
        Set<Id> patientsSeenInRequest = new Set<Id>();
        for (Admission__c admission : candidates) {
            if (activeAdmissionByPatient.containsKey(admission.Patient__c)
                || patientsSeenInRequest.contains(admission.Patient__c)) {
                Admission__c activeAdmission = activeAdmissionByPatient.get(admission.Patient__c);
                String detail = activeAdmission == null
                    ? 'another admission in this request'
                    : activeAdmission.Name + ' (' + activeAdmission.Status__c + ')';
                admission.Patient__c.addError(
                    'This patient already has an active Admission: ' + detail +
                    '. Discharge or cancel it before creating another Admission.'
                );
            } else {
                patientsSeenInRequest.add(admission.Patient__c);
            }
        }
    }

    private static Boolean isActiveAdmission(String status) {
        return status != 'Discharged' && status != 'Cancelled';
    }
    private static Boolean isLinkingPatients = false;

    public static void handleBeforeInsert(List<Admission__c> admissions) {
        prepareAdmissions(admissions);
        populateInsuranceCoverage(admissions);
        validateInsurancePolicy(admissions);
    }

    public static void handleBeforeUpdate(List<Admission__c> admissions, Map<Id, Admission__c> oldMap) {
        prepareAdmissions(admissions);
        populateInsuranceCoverage(admissions);
        moveUnpaidDischargesToPending(admissions, oldMap);
        StatusTransitionValidator.validateTransitions(admissions, oldMap, 'Admission__c', 'Status__c');
        StatusTransitionValidator.validateTransitions(admissions, oldMap, 'Admission__c', 'Approval_Status__c');
        StatusTransitionValidator.validateTransitions(admissions, oldMap, 'Admission__c', 'Emergency_SLA_Status__c');
        validateInsurancePolicy(admissions);
    }

    public static void validateInsurancePolicy(List<Admission__c> admissions) {
        for (Admission__c admission : admissions) {
            if (admission.Insurance_Company__c != null && String.isBlank(admission.Insurance_Policy_Number__c)) {
                admission.Insurance_Policy_Number__c.addError('Insurance Policy Number cannot be empty when an Insurance Company is selected.');
            }
        }
    }

    public static void handleAfterInsert(List<Admission__c> admissions) {
        createPatientsForAdmissions(admissions);
        updatePatientStatus(admissions, null);
        updateLinkedAppointments(admissions);
        enqueueInsuranceVerification(admissions, null);
        syncInsurancePolicyToInvoices(admissions, null);
    }

    public static void handleAfterUpdate(List<Admission__c> admissions, Map<Id, Admission__c> oldMap) {
        createPatientsForAdmissions(admissions);
        updatePatientStatus(admissions, oldMap);
        updateLinkedAppointments(admissions);
        releaseBedAllocationsOnDischarge(admissions, oldMap);
        enqueueInsuranceVerification(admissions, oldMap);
        syncInsurancePolicyToInvoices(admissions, oldMap);
    }

    private static void prepareAdmissions(List<Admission__c> admissions) {
        Set<Id> appointmentIds = new Set<Id>();
        Set<Id> roomIds = new Set<Id>();
        for (Admission__c admission : admissions) {
            if (admission.Appointment__c != null) {
                appointmentIds.add(admission.Appointment__c);
            }
            if (admission.Room__c != null) {
                roomIds.add(admission.Room__c);
            }
        }

        Map<Id, Appointment__c> appointments = appointmentIds.isEmpty()
            ? new Map<Id, Appointment__c>()
            : new Map<Id, Appointment__c>([
                SELECT Id,
                       Patient__c,
                       Patient__r.Name,
                       Patient__r.Phone__c,
                       Patient__r.Email__c,
                       Patient__r.Gender__c,
                       Patient__r.Blood_Group__c,
                       Patient__r.Aadhaar_Last_4__c,
                       Patient__r.Address__c,
                       Doctor__c,
                       Department__c,
                       Priority__c,
                       Symptoms__c
                FROM Appointment__c
                WHERE Id IN :appointmentIds
            ]);

        Map<Id, Room__c> rooms = roomIds.isEmpty()
            ? new Map<Id, Room__c>()
            : new Map<Id, Room__c>([
                SELECT Id, Ward__c, Price__c
                FROM Room__c
                WHERE Id IN :roomIds
            ]);

        for (Admission__c admission : admissions) {
            if (admission.Appointment__c != null) {
                Appointment__c appointment = appointments.get(admission.Appointment__c);
                if (appointment != null) {
                    admission.Patient__c = appointment.Patient__c;
                    admission.Doctor__c = appointment.Doctor__c;
                    admission.Department__c = appointment.Department__c;
                    admission.Priority__c = appointment.Priority__c;
                    admission.Symptoms__c = appointment.Symptoms__c;

                    if (appointment.Patient__c != null) {
                        admission.Patient_Name__c = appointment.Patient__r.Name;
                        admission.Intake_Patient_Name__c = appointment.Patient__r.Name;
                        admission.Phone__c = appointment.Patient__r.Phone__c;
                        admission.Email__c = appointment.Patient__r.Email__c;
                        admission.Gender__c = appointment.Patient__r.Gender__c;
                        admission.Blood_Group__c = appointment.Patient__r.Blood_Group__c;
                        admission.Aadhaar_Last_4__c = appointment.Patient__r.Aadhaar_Last_4__c;
                        admission.Address__c = appointment.Patient__r.Address__c;
                    }
                }
            }

            if (admission.Room__c != null) {
                Room__c room = rooms.get(admission.Room__c);
                if (room != null) {
                    admission.Ward__c = room.Ward__c;
                    if (admission.Estimated_Cost__c == null && room.Price__c != null) {
                        admission.Estimated_Cost__c = room.Price__c;
                    }
                }
            }
        }
    }

    private static void createPatientsForAdmissions(List<Admission__c> admissions) {
        if (isLinkingPatients || admissions == null || admissions.isEmpty()) {
            return;
        }

        List<Patient__c> patientsToInsert = new List<Patient__c>();
        List<Admission__c> admissionsNeedingPatients = new List<Admission__c>();
        for (Admission__c admission : admissions) {
            if (admission.Patient__c != null) {
                continue;
            }
            admissionsNeedingPatients.add(admission);
            patientsToInsert.add(new Patient__c(
                Name = String.isBlank(admission.Patient_Name__c) ? 'Patient ' + admission.Name : admission.Patient_Name__c,
                Phone__c = admission.Phone__c,
                Email__c = admission.Email__c,
                Gender__c = admission.Gender__c,
                Blood_Group__c = admission.Blood_Group__c,
                Aadhaar_Last_4__c = admission.Aadhaar_Last_4__c,
                Address__c = admission.Address__c,
                Patient_Category__c = 'Normal',
                Status__c = derivePatientStatus(admission.Status__c)
            ));
        }

        if (patientsToInsert.isEmpty()) {
            return;
        }

        Database.insert(patientsToInsert, AccessLevel.SYSTEM_MODE);

        List<Admission__c> admissionsToUpdate = new List<Admission__c>();
        for (Integer i = 0; i < admissionsNeedingPatients.size(); i++) {
            admissionsToUpdate.add(new Admission__c(
                Id = admissionsNeedingPatients[i].Id,
                Patient__c = patientsToInsert[i].Id
            ));
        }

        isLinkingPatients = true;
        try {
            Database.update(admissionsToUpdate, AccessLevel.SYSTEM_MODE);
        } finally {
            isLinkingPatients = false;
        }
    }

    private static void updatePatientStatus(List<Admission__c> admissions, Map<Id, Admission__c> oldMap) {
        Map<Id, String> patientStatusMap = new Map<Id, String>();
        for (Admission__c admission : admissions) {
            if (admission.Patient__c == null || admission.Status__c == null) {
                continue;
            }
            if (oldMap != null && oldMap.get(admission.Id).Status__c == admission.Status__c) {
                continue;
            }
            patientStatusMap.put(admission.Patient__c, derivePatientStatus(admission.Status__c));
        }

        List<Patient__c> patientsToUpdate = new List<Patient__c>();
        for (Id patientId : patientStatusMap.keySet()) {
            patientsToUpdate.add(new Patient__c(Id = patientId, Status__c = patientStatusMap.get(patientId)));
        }
        if (!patientsToUpdate.isEmpty()) {
            PatientTriggerHandler.isSyncing = true;
            try {
                Database.update(patientsToUpdate, AccessLevel.SYSTEM_MODE);
            } finally {
                PatientTriggerHandler.isSyncing = false;
            }
        }
    }

    private static String derivePatientStatus(String admissionStatus) {
        if (admissionStatus == 'Admitted' || admissionStatus == 'Pending Discharge') {
            return 'Admitted';
        }
        if (admissionStatus == 'Discharged') {
            return 'Discharged';
        }
        return 'Active';
    }

    private static void moveUnpaidDischargesToPending(
        List<Admission__c> admissions,
        Map<Id, Admission__c> oldMap
    ) {
        Set<Id> dischargeAdmissionIds = new Set<Id>();
        for (Admission__c admission : admissions) {
            Admission__c oldAdmission = oldMap == null ? null : oldMap.get(admission.Id);
            if (admission.Status__c == 'Discharged'
                && (oldAdmission == null || oldAdmission.Status__c != 'Discharged')) {
                dischargeAdmissionIds.add(admission.Id);
            }
        }
        if (dischargeAdmissionIds.isEmpty()) {
            return;
        }

        Set<Id> admissionsWithPendingPayment = new Set<Id>();
        for (Invoice__c invoice : [
            SELECT Admission__c, Net_Payable__c, Payment_Status__c
            FROM Invoice__c
            WHERE Admission__c IN :dischargeAdmissionIds
            AND Net_Payable__c > 0
        ]) {
            if (invoice.Payment_Status__c != 'Paid' && invoice.Payment_Status__c != 'Cancelled') {
                admissionsWithPendingPayment.add(invoice.Admission__c);
            }
        }

        for (Admission__c admission : admissions) {
            if (admissionsWithPendingPayment.contains(admission.Id)) {
                admission.Status__c = 'Pending Discharge';
                admission.Actual_Discharge_Date_Time__c = null;
                admission.Discharge_Date__c = null;
            }
        }
    }

    private static void updateLinkedAppointments(List<Admission__c> admissions) {
        Set<Id> appointmentIds = new Set<Id>();
        Map<Id, Admission__c> apptToAdmissionMap = new Map<Id, Admission__c>();
        for (Admission__c admission : admissions) {
            if (admission.Appointment__c != null) {
                appointmentIds.add(admission.Appointment__c);
                apptToAdmissionMap.put(admission.Appointment__c, admission);
            }
        }
        if (appointmentIds.isEmpty()) {
            return;
        }

        Map<Id, Appointment__c> appointmentsMap = new Map<Id, Appointment__c>([
            SELECT Id, Appointment_Date__c, Appointment_Date_Time__c, Appointment_Time__c, Patient__c, Doctor__c, Department__c 
            FROM Appointment__c 
            WHERE Id IN :appointmentIds
        ]);

        List<Appointment__c> appointmentsToUpdate = new List<Appointment__c>();
        for (Id apptId : appointmentIds) {
            Appointment__c appt = appointmentsMap.get(apptId);
            Admission__c adm = apptToAdmissionMap.get(apptId);
            if (appt == null || adm == null) continue;

            Appointment__c updatedAppt = new Appointment__c(
                Id = apptId,
                Has_Admission__c = true
            );
            
            // Safe-guard 1: Appointment_Date__c
            if (appt.Appointment_Date__c == null) {
                if (appt.Appointment_Date_Time__c != null) {
                    updatedAppt.Appointment_Date__c = appt.Appointment_Date_Time__c.dateGmt();
                } else if (adm.Admission_Date_Time__c != null) {
                    updatedAppt.Appointment_Date__c = adm.Admission_Date_Time__c.dateGmt();
                } else {
                    updatedAppt.Appointment_Date__c = Date.today();
                }
            }
            
            // Safe-guard 2: Appointment_Time__c
            if (appt.Appointment_Time__c == null) {
                updatedAppt.Appointment_Time__c = '10:00';
            }

            // Safe-guard 3: Patient__c
            if (appt.Patient__c == null) {
                updatedAppt.Patient__c = adm.Patient__c;
            }

            // Safe-guard 4: Doctor__c
            if (appt.Doctor__c == null) {
                updatedAppt.Doctor__c = adm.Doctor__c;
            }

            // Safe-guard 5: Department__c
            if (appt.Department__c == null) {
                updatedAppt.Department__c = adm.Department__c;
            }
            
            // Safe-guard 6: Adjust date to today if it is in the past to prevent Prevent_Past_Appointment_Date validation failure
            if (updatedAppt.Appointment_Date__c != null && updatedAppt.Appointment_Date__c < Date.today()) {
                updatedAppt.Appointment_Date__c = Date.today();
            } else if (appt.Appointment_Date__c != null && appt.Appointment_Date__c < Date.today()) {
                updatedAppt.Appointment_Date__c = Date.today();
            }

            appointmentsToUpdate.add(updatedAppt);
        }
        if (!appointmentsToUpdate.isEmpty()) {
            try {
                Database.update(appointmentsToUpdate, AccessLevel.SYSTEM_MODE);
            } catch (Exception ex) {
                System.debug('Error updating linked Appointments: ' + ex.getMessage());
            }
        }
    }

    private static void releaseBedAllocationsOnDischarge(List<Admission__c> admissions, Map<Id, Admission__c> oldMap) {
        Set<Id> dischargedAdmissionIds = new Set<Id>();
        Map<Id, DateTime> dischargeTimes = new Map<Id, DateTime>();

        for (Admission__c admission : admissions) {
            Boolean isDischargedNow = (admission.Status__c == 'Discharged' && 
                                       (oldMap == null || oldMap.get(admission.Id).Status__c != 'Discharged'));
            if (isDischargedNow) {
                dischargedAdmissionIds.add(admission.Id);
                DateTime dischargeTime = admission.Actual_Discharge_Date_Time__c != null 
                                            ? admission.Actual_Discharge_Date_Time__c 
                                            : System.now();
                dischargeTimes.put(admission.Id, dischargeTime);
            }
        }

        if (dischargedAdmissionIds.isEmpty()) {
            return;
        }

        List<Bed_Allocation__c> allocationsToRelease = [
            SELECT Id, Status__c, Start_Date_Time__c, End_Date_Time__c, Admission__c
            FROM Bed_Allocation__c
            WHERE Admission__c IN :dischargedAdmissionIds
            AND Status__c IN ('Reserved', 'Occupied')
            AND (End_Date_Time__c = null OR End_Date_Time__c > :System.now())
        ];

        if (allocationsToRelease.isEmpty()) {
            return;
        }

        for (Bed_Allocation__c allocation : allocationsToRelease) {
            allocation.Status__c = 'Released';
            DateTime endDateTime = dischargeTimes.get(allocation.Admission__c);
            if (allocation.Start_Date_Time__c != null && endDateTime <= allocation.Start_Date_Time__c) {
                endDateTime = allocation.Start_Date_Time__c.addSeconds(1);
            }
            allocation.End_Date_Time__c = endDateTime;
        }

        Database.update(allocationsToRelease, AccessLevel.SYSTEM_MODE);
    }

    private static void populateInsuranceCoverage(List<Admission__c> admissions) {
        Set<Id> insuranceCompanyIds = new Set<Id>();
        for (Admission__c admission : admissions) {
            if (admission.Insurance_Company__c != null) {
                insuranceCompanyIds.add(admission.Insurance_Company__c);
            }
        }
        
        Map<Id, Insurance_Company__c> insuranceCompanies = insuranceCompanyIds.isEmpty()
            ? new Map<Id, Insurance_Company__c>()
            : new Map<Id, Insurance_Company__c>([
                SELECT Id, Standard_Discount__c
                FROM Insurance_Company__c
                WHERE Id IN :insuranceCompanyIds
            ]);
            
        for (Admission__c admission : admissions) {
            if (admission.Insurance_Company__c != null) {
                Insurance_Company__c comp = insuranceCompanies.get(admission.Insurance_Company__c);
                if (comp != null) {
                    admission.Insurance_Coverage__c = comp.Standard_Discount__c;
                }
            } else {
                admission.Insurance_Coverage__c = null;
            }
        }
    }

    private static void enqueueInsuranceVerification(List<Admission__c> admissions, Map<Id, Admission__c> oldMap) {
        List<Id> idsToVerify = new List<Id>();
        for (Admission__c admission : admissions) {
            Admission__c oldAdm = (oldMap != null) ? oldMap.get(admission.Id) : null;
            Boolean isNewOrPolicyChanged = (oldAdm == null || oldAdm.Insurance_Policy_Number__c != admission.Insurance_Policy_Number__c);
            
            if (admission.Insurance_Policy_Number__c != null 
                && !admission.Insurance_Verified__c 
                && admission.Insurance_Policy__c == null
                && isNewOrPolicyChanged) {
                idsToVerify.add(admission.Id);
            }
        }
        
        if (!idsToVerify.isEmpty()) {
            System.enqueueJob(new InsuranceVerificationQueueable(idsToVerify));
        }
    }

    private static void syncInsurancePolicyToInvoices(List<Admission__c> admissions, Map<Id, Admission__c> oldMap) {
        Map<Id, Id> admissionToPolicyMap = new Map<Id, Id>();
        for (Admission__c admission : admissions) {
            Admission__c oldAdm = (oldMap != null) ? oldMap.get(admission.Id) : null;
            Boolean policyChanged = (oldAdm == null || oldAdm.Insurance_Policy__c != admission.Insurance_Policy__c);
            if (policyChanged && admission.Insurance_Policy__c != null) {
                admissionToPolicyMap.put(admission.Id, admission.Insurance_Policy__c);
            }
        }
        
        if (admissionToPolicyMap.isEmpty()) {
            return;
        }
        
        List<Invoice__c> invoicesToUpdate = [
            SELECT Id, Admission__c, Insurance_Policy__c, Invoice_Date__c
            FROM Invoice__c
            WHERE Admission__c IN :admissionToPolicyMap.keySet()
        ];
        
        if (invoicesToUpdate.isEmpty()) {
            return;
        }
        
        for (Invoice__c invoice : invoicesToUpdate) {
            invoice.Insurance_Policy__c = admissionToPolicyMap.get(invoice.Admission__c);
        }
        
        Database.update(invoicesToUpdate, AccessLevel.SYSTEM_MODE);
        
        Set<Id> invoiceIds = new Set<Id>();
        for (Invoice__c invoice : invoicesToUpdate) {
            invoiceIds.add(invoice.Id);
        }
        InvoiceBillingService.calculateInvoiceTotals(invoiceIds);
    }
}
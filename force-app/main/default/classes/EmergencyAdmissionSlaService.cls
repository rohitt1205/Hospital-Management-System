public without sharing class EmergencyAdmissionSlaService {
    private static final String EMERGENCY = 'Emergency';
    private static final String STATUS_ADMITTED = 'Admitted';
    private static final String STATUS_DISCHARGED = 'Discharged';
    private static final String STATUS_CANCELLED = 'Cancelled';
    private static final String APPROVAL_NOT_REQUIRED = 'Not Required';
    private static final String SLA_ON_TIME = 'On Time';
    private static final String SLA_AT_RISK = 'At Risk';
    private static final String SLA_ESCALATED = 'Escalated';

    public static void applyBeforeSave(List<Admission__c> admissions, Map<Id, Admission__c> oldMap) {
        if (admissions == null || admissions.isEmpty()) {
            return;
        }

        List<Admission__c> emergencyAdmissions = new List<Admission__c>();
        Set<Id> requestedDepartmentIds = new Set<Id>();
        Set<Id> selectedDoctorIds = new Set<Id>();
        for (Admission__c admission : admissions) {
            applyPriority(admission);
            if (!isEmergency(admission)) {
                continue;
            }
            emergencyAdmissions.add(admission);
            if (admission.Doctor__c != null) {
                selectedDoctorIds.add(admission.Doctor__c);
            }
            if (admission.Department__c != null && admission.Doctor__c == null) {
                requestedDepartmentIds.add(admission.Department__c);
            }
        }

        Map<Id, Doctor__c> selectedDoctors = selectedDoctorIds.isEmpty()
            ? new Map<Id, Doctor__c>()
            : new Map<Id, Doctor__c>([
                SELECT Id, Department__c
                FROM Doctor__c
                WHERE Id IN :selectedDoctorIds
            ]);
        for (Admission__c admission : emergencyAdmissions) {
            if (admission.Doctor__c != null && admission.Department__c != null) {
                Doctor__c selectedDoctor = selectedDoctors.get(admission.Doctor__c);
                if (selectedDoctor == null || selectedDoctor.Department__c != admission.Department__c) {
                    admission.Doctor__c = null;
                    requestedDepartmentIds.add(admission.Department__c);
                }
            }
        }
        Map<Id, Id> doctorByDepartment = findAvailableDoctors(requestedDepartmentIds);
        Datetime nowValue = System.now();

        for (Admission__c admission : emergencyAdmissions) {
            if (admission.Admission_Date_Time__c == null) {
                admission.Admission_Date_Time__c = nowValue;
            }
            if (admission.Doctor_Assignment_Due__c == null) {
                admission.Doctor_Assignment_Due__c = nowValue.addMinutes(15);
            }

            admission.Status__c = STATUS_ADMITTED;
            admission.Approval_Status__c = APPROVAL_NOT_REQUIRED;

            if (admission.Doctor__c == null && admission.Department__c != null) {
                admission.Doctor__c = doctorByDepartment.get(admission.Department__c);
            }

            Admission__c oldAdmission = oldMap == null ? null : oldMap.get(admission.Id);
            Boolean doctorWasAssignedNow = admission.Doctor__c != null
                && (oldAdmission == null || oldAdmission.Doctor__c == null || oldAdmission.Doctor__c != admission.Doctor__c);
            if (doctorWasAssignedNow && admission.Doctor_Assigned_At__c == null) {
                admission.Doctor_Assigned_At__c = nowValue;
            }

            if (admission.Doctor__c != null) {
                if (admission.Emergency_Escalated__c == true || admission.Emergency_SLA_Status__c == SLA_ESCALATED) {
                    admission.Emergency_SLA_Status__c = SLA_ESCALATED;
                } else {
                    admission.Emergency_SLA_Status__c = SLA_ON_TIME;
                }
            } else {
                admission.Doctor_Assigned_At__c = null;
                if (admission.Emergency_SLA_Status__c == null || admission.Emergency_SLA_Status__c == SLA_ON_TIME) {
                    admission.Emergency_SLA_Status__c = SLA_AT_RISK;
                }
            }
        }
    }

    public static Integer escalateOverdueAdmissions() {
        Datetime nowValue = System.now();
        List<Admission__c> overdueAdmissions = [
            SELECT Id, Name, Patient_Name__c, Phone__c, Patient__r.Name, Patient__r.Phone__c,
                   Department__c, Department__r.Name,
                   Doctor_Assignment_Due__c, Status__c, Emergency_Escalated__c
            FROM Admission__c
            WHERE Admission_Type__c = :EMERGENCY
            AND Doctor__c = null
            AND Emergency_Escalated__c = false
            AND Doctor_Assignment_Due__c <= :nowValue
            AND Status__c NOT IN (:STATUS_DISCHARGED, :STATUS_CANCELLED)
            WITH SYSTEM_MODE
            LIMIT 200
        ];

        if (overdueAdmissions.isEmpty()) {
            return 0;
        }

        Id taskOwnerId = findHospitalAdminUserId();
        List<Task> tasks = new List<Task>();
        List<Admission__c> updates = new List<Admission__c>();
        for (Admission__c admission : overdueAdmissions) {
            tasks.add(new Task(
                WhatId = admission.Id,
                OwnerId = taskOwnerId,
                Subject = 'Emergency admission pending doctor assignment: ' + admission.Name,
                Priority = 'High',
                Status = 'Not Started',
                ActivityDate = Date.today(),
                Description =
                    'Emergency admission has breached the 15 minute doctor assignment SLA.' +
                    '\nAdmission: ' + admission.Name +
                    '\nPatient: ' + blankToDash(preferredPatientName(admission)) +
                    '\nPhone: ' + blankToDash(preferredPatientPhone(admission)) +
                    '\nDepartment: ' + (admission.Department__r == null ? '-' : admission.Department__r.Name) +
                    '\nDue At: ' + String.valueOf(admission.Doctor_Assignment_Due__c)
            ));
            updates.add(new Admission__c(
                Id = admission.Id,
                Emergency_Escalated__c = true,
                Emergency_SLA_Status__c = SLA_ESCALATED
            ));
        }

        Database.insert(tasks, AccessLevel.SYSTEM_MODE);
        Database.update(updates, AccessLevel.SYSTEM_MODE);
        return overdueAdmissions.size();
    }

    private static Boolean isEmergency(Admission__c admission) {
        return admission != null && admission.Admission_Type__c == EMERGENCY;
    }

    private static void applyPriority(Admission__c admission) {
        if (admission == null || String.isBlank(admission.Admission_Type__c)) {
            return;
        }
        if (admission.Admission_Type__c == 'Emergency') {
            admission.Priority__c = 'Critical';
        } else if (admission.Admission_Type__c == 'Planned') {
            admission.Priority__c = 'Normal';
        } else if (admission.Admission_Type__c == 'Doctor Override') {
            admission.Priority__c = 'High';
        }
    }

    private static Map<Id, Id> findAvailableDoctors(Set<Id> requestedDepartmentIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (requestedDepartmentIds == null || requestedDepartmentIds.isEmpty()) {
            return result;
        }

        Set<Id> candidateDepartmentIds = new Set<Id>();
        candidateDepartmentIds.addAll(requestedDepartmentIds);

        List<Doctor__c> doctors = [
            SELECT Id, Department__c
            FROM Doctor__c
            WHERE Department__c IN :candidateDepartmentIds
            ORDER BY Name ASC
            LIMIT 500
        ];
        if (doctors.isEmpty()) {
            return result;
        }

        Set<Id> doctorIds = new Map<Id, Doctor__c>(doctors).keySet();
        Map<Id, Integer> todayLoadByDoctor = new Map<Id, Integer>();
        for (AggregateResult aggregateRow : [
            SELECT Doctor__c doctorId, COUNT(Id) total
            FROM Admission__c
            WHERE Doctor__c IN :doctorIds
            AND DAY_ONLY(Admission_Date_Time__c) = TODAY
            AND Status__c NOT IN (:STATUS_DISCHARGED, :STATUS_CANCELLED)
            GROUP BY Doctor__c
        ]) {
            todayLoadByDoctor.put((Id) aggregateRow.get('doctorId'), (Integer) aggregateRow.get('total'));
        }

        for (Id departmentId : requestedDepartmentIds) {
            Doctor__c selected = selectLeastLoadedDoctor(doctors, todayLoadByDoctor, departmentId);
            if (selected != null) {
                result.put(departmentId, selected.Id);
                todayLoadByDoctor.put(selected.Id, getDoctorLoad(todayLoadByDoctor, selected.Id) + 1);
            }
        }
        return result;
    }

    private static Doctor__c selectLeastLoadedDoctor(List<Doctor__c> doctors, Map<Id, Integer> loadByDoctor, Id departmentId) {
        Doctor__c selected;
        Integer selectedLoad;
        for (Doctor__c doctor : doctors) {
            if (doctor.Department__c != departmentId) {
                continue;
            }
            Integer doctorLoad = getDoctorLoad(loadByDoctor, doctor.Id);
            if (selected == null || doctorLoad < selectedLoad) {
                selected = doctor;
                selectedLoad = doctorLoad;
            }
        }
        return selected;
    }

    private static Integer getDoctorLoad(Map<Id, Integer> loadByDoctor, Id doctorId) {
        return loadByDoctor != null && loadByDoctor.containsKey(doctorId) ? loadByDoctor.get(doctorId) : 0;
    }

    private static Id findHospitalAdminUserId() {
        List<User> hospitalAdmins = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND UserRole.Name = 'Hospital_Admin'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 1
        ];
        if (!hospitalAdmins.isEmpty()) {
            return hospitalAdmins[0].Id;
        }
        
        List<User> sysAdmins = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND Profile.Name = 'System Administrator'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 1
        ];
        if (!sysAdmins.isEmpty()) {
            return sysAdmins[0].Id;
        }
        
        return UserInfo.getUserId();
    }

    private static String blankToDash(String value) {
        return String.isBlank(value) ? '-' : value;
    }

    private static String preferredPatientName(Admission__c admission) {
        if (admission == null) {
            return null;
        }
        if (admission.Patient__r != null && !String.isBlank(admission.Patient__r.Name)) {
            return admission.Patient__r.Name;
        }
        return admission.Patient_Name__c;
    }

    private static String preferredPatientPhone(Admission__c admission) {
        if (admission == null) {
            return null;
        }
        if (admission.Patient__r != null && !String.isBlank(admission.Patient__r.Phone__c)) {
            return admission.Patient__r.Phone__c;
        }
        return admission.Phone__c;
    }
}
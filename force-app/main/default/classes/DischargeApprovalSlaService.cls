public without sharing class DischargeApprovalSlaService {
    
    public static Integer escalateOverdueDischarges() {
        Datetime nowValue = System.now();
        Datetime threshold = nowValue.addMinutes(-5);

        // Query admissions where Status is Discharged, Approval Status is Pending Approval,
        // and Actual Discharge Date/Time was set more than 5 minutes ago.
        List<Admission__c> pendingDischarges = [
            SELECT Id, Name, Patient_Name__c, Phone__c, Patient__r.Name, Patient__r.Phone__c,
                   Actual_Discharge_Date_Time__c, Status__c, Approval_Status__c
            FROM Admission__c
            WHERE Status__c = 'Discharged'
            AND Approval_Status__c = 'Pending Approval'
            AND Actual_Discharge_Date_Time__c <= :threshold
            LIMIT 200
        ];

        if (pendingDischarges.isEmpty()) {
            return 0;
        }

        // To prevent duplicate task creation, check which admissions already have an active escalation task.
        Set<Id> admissionIds = new Set<Id>();
        for (Admission__c adm : pendingDischarges) {
            admissionIds.add(adm.Id);
        }

        List<Task> existingTasks = [
            SELECT WhatId 
            FROM Task 
            WHERE WhatId IN :admissionIds 
            AND Subject LIKE 'Discharge approval pending:%'
            AND Status != 'Completed'
        ];

        Set<Id> alreadyEscalatedIds = new Set<Id>();
        for (Task t : existingTasks) {
            alreadyEscalatedIds.add(t.WhatId);
        }

        Id taskOwnerId = findHospitalAdminUserId();
        List<Task> tasksToInsert = new List<Task>();

        for (Admission__c admission : pendingDischarges) {
            if (alreadyEscalatedIds.contains(admission.Id)) {
                continue;
            }

            tasksToInsert.add(new Task(
                WhatId = admission.Id,
                OwnerId = taskOwnerId,
                Subject = 'Discharge approval pending: ' + admission.Name,
                Priority = 'High',
                Status = 'Not Started',
                ActivityDate = Date.today(),
                Description = 'Discharge approval has breached the 5 minute SLA.' +
                              '\nAdmission: ' + admission.Name +
                              '\nPatient: ' + blankToDash(preferredPatientName(admission)) +
                              '\nPhone: ' + blankToDash(preferredPatientPhone(admission)) +
                              '\nDischarge Initiated At: ' + String.valueOf(admission.Actual_Discharge_Date_Time__c)
            ));
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }

        return tasksToInsert.size();
    }

    private static Id findHospitalAdminUserId() {
        List<User> hospitalAdmins = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND UserRole.Name = 'Hospital_Admin'
            ORDER BY Name ASC
            LIMIT 1
        ];
        if (!hospitalAdmins.isEmpty()) {
            return hospitalAdmins[0].Id;
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
public with sharing class EmergencyTaskDoctorAssignmentController {
    @AuraEnabled(cacheable=true)
    public static AssignmentContext getAssignmentContext(Id taskId) {
        if (taskId == null) {
            throw new AuraHandledException('Task Id is required.');
        }

        Task taskRecord = [
            SELECT Id, Subject, Status, WhatId
            FROM Task
            WHERE Id = :taskId
            LIMIT 1
        ];

        AssignmentContext context = new AssignmentContext();
        context.taskId = taskRecord.Id;
        context.taskSubject = taskRecord.Subject;
        context.taskStatus = taskRecord.Status;
        context.isAdmissionTask = taskRecord.WhatId != null
            && String.valueOf(taskRecord.WhatId).startsWith(Admission__c.SObjectType.getDescribe().getKeyPrefix());

        if (!context.isAdmissionTask) {
            context.message = 'This task is not related to an admission.';
            return context;
        }

        Admission__c admission = [
            SELECT Id, Name, Patient__c, Patient__r.Name, Patient__r.Phone__c,
                   Patient_Name__c, Phone__c, Department__c, Department__r.Name,
                   Doctor__c, Doctor__r.Name, Admission_Type__c, Emergency_SLA_Status__c,
                   Emergency_Escalated__c, Doctor_Assignment_Due__c
            FROM Admission__c
            WHERE Id = :taskRecord.WhatId
            LIMIT 1
        ];

        context.admissionId = admission.Id;
        context.admissionName = admission.Name;
        context.departmentId = admission.Department__c;
        context.departmentName = admission.Department__r == null ? null : admission.Department__r.Name;
        context.patientName = preferredPatientName(admission);
        context.patientPhone = preferredPatientPhone(admission);
        context.currentDoctorId = admission.Doctor__c;
        context.currentDoctorName = admission.Doctor__r == null ? null : admission.Doctor__r.Name;
        context.assignmentDue = admission.Doctor_Assignment_Due__c;
        context.slaStatus = admission.Emergency_SLA_Status__c;
        context.isEmergencyAdmission = admission.Admission_Type__c == 'Emergency';

        if (!context.isEmergencyAdmission) {
            context.message = 'This admission is not an emergency admission.';
            return context;
        }

        if (admission.Department__c == null) {
            context.message = 'Select a department on the admission before assigning a doctor.';
            return context;
        }

        for (Doctor__c doctor : [
            SELECT Id, Name, Specialization__c
            FROM Doctor__c
            WHERE Department__c = :admission.Department__c
            ORDER BY Name ASC
            LIMIT 200
        ]) {
            DoctorOption option = new DoctorOption();
            option.value = doctor.Id;
            option.label = String.isBlank(doctor.Specialization__c)
                ? doctor.Name
                : doctor.Name + ' - ' + doctor.Specialization__c;
            context.doctors.add(option);
        }

        if (context.currentDoctorId != null) {
            context.message = 'A doctor is already assigned.';
        } else if (context.doctors.isEmpty()) {
            context.message = 'No doctors are available in ' + context.departmentName + '. Add a doctor in this department, then refresh this task.';
        }

        return context;
    }

    @AuraEnabled
    public static AssignmentResult assignDoctor(Id taskId, Id doctorId) {
        if (taskId == null || doctorId == null) {
            throw new AuraHandledException('Task and doctor are required.');
        }

        Task taskRecord = [
            SELECT Id, Status, WhatId
            FROM Task
            WHERE Id = :taskId
            LIMIT 1
            FOR UPDATE
        ];
        if (taskRecord.WhatId == null || !String.valueOf(taskRecord.WhatId).startsWith(Admission__c.SObjectType.getDescribe().getKeyPrefix())) {
            throw new AuraHandledException('This task is not related to an admission.');
        }

        Admission__c admission = [
            SELECT Id, Department__c, Doctor__c, Doctor_Assigned_At__c,
                   Emergency_Escalated__c, Emergency_SLA_Status__c
            FROM Admission__c
            WHERE Id = :taskRecord.WhatId
            LIMIT 1
            FOR UPDATE
        ];
        Doctor__c doctor = [
            SELECT Id, Name, Department__c
            FROM Doctor__c
            WHERE Id = :doctorId
            LIMIT 1
        ];
        if (admission.Department__c == null || doctor.Department__c != admission.Department__c) {
            throw new AuraHandledException('Select a doctor from the admission department only.');
        }

        admission.Doctor__c = doctor.Id;
        admission.Doctor_Assigned_At__c = System.now();
        if (admission.Emergency_Escalated__c == true) {
            admission.Emergency_SLA_Status__c = 'Escalated';
        }
        update admission;

        taskRecord.Status = 'Completed';
        update taskRecord;

        AssignmentResult result = new AssignmentResult();
        result.admissionId = admission.Id;
        result.doctorName = doctor.Name;
        result.taskId = taskRecord.Id;
        result.taskStatus = taskRecord.Status;
        return result;
    }

    private static String preferredPatientName(Admission__c admission) {
        if (admission.Patient__r != null && !String.isBlank(admission.Patient__r.Name)) {
            return admission.Patient__r.Name;
        }
        return admission.Patient_Name__c;
    }

    private static String preferredPatientPhone(Admission__c admission) {
        if (admission.Patient__r != null && !String.isBlank(admission.Patient__r.Phone__c)) {
            return admission.Patient__r.Phone__c;
        }
        return admission.Phone__c;
    }

    public class AssignmentContext {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String taskSubject;
        @AuraEnabled public String taskStatus;
        @AuraEnabled public Boolean isAdmissionTask;
        @AuraEnabled public Boolean isEmergencyAdmission;
        @AuraEnabled public Id admissionId;
        @AuraEnabled public String admissionName;
        @AuraEnabled public Id departmentId;
        @AuraEnabled public String departmentName;
        @AuraEnabled public String patientName;
        @AuraEnabled public String patientPhone;
        @AuraEnabled public Id currentDoctorId;
        @AuraEnabled public String currentDoctorName;
        @AuraEnabled public Datetime assignmentDue;
        @AuraEnabled public String slaStatus;
        @AuraEnabled public String message;
        @AuraEnabled public List<DoctorOption> doctors = new List<DoctorOption>();
    }

    public class DoctorOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class AssignmentResult {
        @AuraEnabled public Id admissionId;
        @AuraEnabled public Id taskId;
        @AuraEnabled public String doctorName;
        @AuraEnabled public String taskStatus;
    }
}
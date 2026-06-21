@isTest
private class EmergencyAdmissionSlaServiceTest {
    private class EmergencySlaMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void emergencyAdmissionAssignsMatchingDepartmentDoctor() {
        Test.setMock(HttpCalloutMock.class, new EmergencySlaMock());
        Department__c department = new Department__c(
            Name = 'Emergency SLA Test Dept',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert department;

        Doctor__c doctor = new Doctor__c(
            Name = 'Emergency SLA Test Doctor',
            Department__c = department.Id,
            Registration_Number__c = 'REG-001'
        );
        insert doctor;

        Test.startTest();
        Admission__c admission = new Admission__c(
            Patient_Name__c = 'Emergency Patient',
            Phone__c = '9999999999',
            Department__c = department.Id,
            Admission_Type__c = 'Emergency'
        );
        insert admission;
        Test.stopTest();

        Admission__c savedAdmission = [
            SELECT Doctor__c, Status__c, Priority__c, Approval_Status__c, Emergency_SLA_Status__c,
                   Doctor_Assignment_Due__c, Doctor_Assigned_At__c, Admission_Date_Time__c
            FROM Admission__c
            WHERE Id = :admission.Id
        ];
        System.assertEquals(doctor.Id, savedAdmission.Doctor__c, 'Emergency admission should auto-assign a doctor from the selected department.');
        System.assertEquals('Admitted', savedAdmission.Status__c, 'Emergency admission should be admitted immediately.');
        System.assertEquals('Critical', savedAdmission.Priority__c, 'Emergency admission should become critical priority.');
        System.assertEquals('Not Required', savedAdmission.Approval_Status__c, 'Emergency admission should bypass approval.');
        System.assertEquals('On Time', savedAdmission.Emergency_SLA_Status__c, 'Assigned emergency admission should be on time.');
        System.assertNotEquals(null, savedAdmission.Admission_Date_Time__c, 'Admission date should be filled when omitted.');
        System.assertNotEquals(null, savedAdmission.Doctor_Assignment_Due__c, 'Doctor assignment due time should be populated.');
        System.assertNotEquals(null, savedAdmission.Doctor_Assigned_At__c, 'Doctor assigned time should be populated.');
    }

    @isTest
    static void emergencyDoesNotFallbackToGeneralMedicineDoctor() {
        Test.setMock(HttpCalloutMock.class, new EmergencySlaMock());
        Department__c requestedDepartment = new Department__c(
            Name = 'OPD No Doctor SLA Test Dept',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        Department__c generalMedicine = new Department__c(
            Name = 'General Medicine',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert new List<Department__c>{ requestedDepartment, generalMedicine };

        insert new Doctor__c(
            Name = 'General Medicine Fallback Doctor',
            Department__c = generalMedicine.Id,
            Registration_Number__c = 'REG-002'
        );

        Admission__c admission = new Admission__c(
            Patient_Name__c = 'No Fallback Emergency Patient',
            Phone__c = '7777777777',
            Department__c = requestedDepartment.Id,
            Admission_Type__c = 'Emergency'
        );
        insert admission;

        admission = [
            SELECT Doctor__c, Emergency_SLA_Status__c
            FROM Admission__c
            WHERE Id = :admission.Id
        ];
        System.assertEquals(null, admission.Doctor__c, 'Emergency assignment must not fallback to a doctor from another department.');
        System.assertEquals('At Risk', admission.Emergency_SLA_Status__c, 'No same-department doctor should keep the admission at risk.');
    }

    @isTest
    static void emergencyClearsDoctorFromDifferentDepartment() {
        Test.setMock(HttpCalloutMock.class, new EmergencySlaMock());
        Department__c requestedDepartment = new Department__c(
            Name = 'Wrong Doctor Requested Dept',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        Department__c otherDepartment = new Department__c(
            Name = 'Wrong Doctor Other Dept',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert new List<Department__c>{ requestedDepartment, otherDepartment };

        Doctor__c wrongDoctor = new Doctor__c(
            Name = 'Wrong Department Doctor',
            Department__c = otherDepartment.Id,
            Registration_Number__c = 'REG-003'
        );
        insert wrongDoctor;

        Admission__c admission = new Admission__c(
            Patient_Name__c = 'Wrong Doctor Emergency Patient',
            Phone__c = '7777777778',
            Department__c = requestedDepartment.Id,
            Doctor__c = wrongDoctor.Id,
            Admission_Type__c = 'Emergency'
        );
        insert admission;

        admission = [
            SELECT Doctor__c, Doctor_Assigned_At__c, Emergency_SLA_Status__c
            FROM Admission__c
            WHERE Id = :admission.Id
        ];
        System.assertEquals(null, admission.Doctor__c, 'Cross-department doctor should not remain assigned.');
        System.assertEquals(null, admission.Doctor_Assigned_At__c, 'Assigned-at should stay blank without a valid doctor.');
        System.assertEquals('At Risk', admission.Emergency_SLA_Status__c, 'Wrong doctor department should leave the case at risk.');
    }

    @isTest
    static void nonWalkInAdmissionTypesMapPriority() {
        Test.setMock(HttpCalloutMock.class, new EmergencySlaMock());
        Department__c department = new Department__c(
            Name = 'Priority Mapping Test Dept',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert department;

        List<Admission__c> admissions = new List<Admission__c>{
            new Admission__c(Patient_Name__c = 'Planned Patient', Phone__c = '1111111111', Department__c = department.Id, Admission_Type__c = 'Planned', Priority__c = 'High'),
            new Admission__c(Patient_Name__c = 'Override Patient', Phone__c = '2222222222', Department__c = department.Id, Admission_Type__c = 'Doctor Override', Priority__c = 'Normal'),
            new Admission__c(Patient_Name__c = 'Walk In Patient', Phone__c = '3333333333', Department__c = department.Id, Admission_Type__c = 'Walk In', Priority__c = 'High')
        };
        insert admissions;

        Map<Id, Admission__c> saved = new Map<Id, Admission__c>([
            SELECT Priority__c
            FROM Admission__c
            WHERE Id IN :admissions
        ]);
        System.assertEquals('Normal', saved.get(admissions[0].Id).Priority__c, 'Planned admissions should be normal priority.');
        System.assertEquals('High', saved.get(admissions[1].Id).Priority__c, 'Doctor Override admissions should be high priority.');
        System.assertEquals('High', saved.get(admissions[2].Id).Priority__c, 'Walk In should keep the selected priority.');
    }

    @isTest
    static void emergencyAdmissionWithoutDoctorEscalatesAfterDueTime() {
        Test.setMock(HttpCalloutMock.class, new EmergencySlaMock());
        Department__c department = new Department__c(
            Name = 'No Doctor Emergency SLA Test Dept',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert department;

        Admission__c admission = new Admission__c(
            Patient_Name__c = 'Unassigned Emergency Patient',
            Phone__c = '8888888888',
            Department__c = department.Id,
            Admission_Type__c = 'Emergency'
        );
        insert admission;

        admission = [
            SELECT Id, Doctor__c, Status__c, Approval_Status__c, Emergency_SLA_Status__c,
                   Emergency_Escalated__c, Doctor_Assignment_Due__c
            FROM Admission__c
            WHERE Id = :admission.Id
        ];
        System.assertEquals(null, admission.Doctor__c, 'Admission should remain unassigned when no doctor exists in the department.');
        System.assertEquals('Admitted', admission.Status__c, 'Emergency admission still bypasses approval and becomes admitted.');
        System.assertEquals('At Risk', admission.Emergency_SLA_Status__c, 'Unassigned emergency admission starts at risk.');

        admission.Doctor_Assignment_Due__c = System.now().addMinutes(-1);
        update admission;

        Test.startTest();
        Integer escalatedCount = EmergencyAdmissionSlaService.escalateOverdueAdmissions();
        Test.stopTest();

        System.assertEquals(1, escalatedCount, 'Exactly one overdue emergency admission should escalate.');
        Admission__c escalatedAdmission = [
            SELECT Emergency_Escalated__c, Emergency_SLA_Status__c
            FROM Admission__c
            WHERE Id = :admission.Id
        ];
        System.assertEquals(true, escalatedAdmission.Emergency_Escalated__c, 'Admission should be marked escalated.');
        System.assertEquals('Escalated', escalatedAdmission.Emergency_SLA_Status__c, 'SLA status should show escalated.');

        Task escalationTask = [
            SELECT WhatId, Subject, Priority, Status
            FROM Task
            WHERE WhatId = :admission.Id
            LIMIT 1
        ];
        System.assertEquals(admission.Id, escalationTask.WhatId, 'Escalation task should be tied to the admission.');
        System.assert(escalationTask.Subject.contains('Emergency admission pending doctor assignment'), 'Escalation task should explain the breach.');
        System.assertEquals('High', escalationTask.Priority);
        System.assertEquals('Not Started', escalationTask.Status);
    }

    @isTest
    static void schedulerInvokesEscalationService() {
        Test.startTest();
        String jobId = System.schedule(
            'Emergency SLA Test Schedule',
            '0 0 0 1 1 ? 2099',
            new EmergencyAdmissionSlaScheduler()
        );
        Test.stopTest();

        CronTrigger scheduledJob = [
            SELECT Id, State
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        System.assertNotEquals(null, scheduledJob.Id, 'Emergency SLA scheduler should be schedulable.');
    }
}
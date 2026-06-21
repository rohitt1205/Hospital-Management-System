@isTest
private class EmergencyTaskDoctorAssignCtrlTest {
    private class EmergencyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void contextUsesLinkedPatientDataAndAssignsSameDepartmentDoctor() {
        Test.setMock(HttpCalloutMock.class, new EmergencyMock());
        Department__c department = new Department__c(
            Name = 'Task Assignment Test Dept',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert department;

        Patient__c patient = new Patient__c(
            Name = 'Task Assignment Patient',
            Phone__c = '9000000001'
        );
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Department__c = department.Id,
            Admission_Type__c = 'Emergency',
            Doctor_Assignment_Due__c = System.now().addMinutes(-10),
            Emergency_Escalated__c = true,
            Emergency_SLA_Status__c = 'Escalated',
            Phone__c = '9000000001'
        );
        insert admission;

        Task escalationTask = new Task(
            WhatId = admission.Id,
            Subject = 'Emergency admission pending doctor assignment: ' + admission.Name,
            Priority = 'High',
            Status = 'Not Started',
            ActivityDate = Date.today()
        );
        insert escalationTask;

        Doctor__c doctor = new Doctor__c(
            Name = 'Task Assignment Doctor',
            Department__c = department.Id,
            Specialization__c = 'Emergency Medicine'
        );
        insert doctor;

        Test.startTest();
        EmergencyTaskDoctorAssignmentController.AssignmentContext context =
            EmergencyTaskDoctorAssignmentController.getAssignmentContext(escalationTask.Id);
        EmergencyTaskDoctorAssignmentController.AssignmentResult result =
            EmergencyTaskDoctorAssignmentController.assignDoctor(escalationTask.Id, doctor.Id);
        Test.stopTest();

        System.assertEquals('Task Assignment Patient', context.patientName);
        System.assertEquals('9000000001', context.patientPhone);
        System.assertEquals(1, context.doctors.size(), 'Same department doctor should be offered.');
        System.assertEquals('Task Assignment Doctor', result.doctorName);

        Admission__c updatedAdmission = [
            SELECT Doctor__c, Doctor_Assigned_At__c, Emergency_SLA_Status__c
            FROM Admission__c
            WHERE Id = :admission.Id
        ];
        System.assertEquals(doctor.Id, updatedAdmission.Doctor__c);
        System.assertNotEquals(null, updatedAdmission.Doctor_Assigned_At__c);
        System.assertEquals('Escalated', updatedAdmission.Emergency_SLA_Status__c, 'Late assignment should keep the breach status.');

        Task updatedTask = [
            SELECT Status
            FROM Task
            WHERE Id = :escalationTask.Id
        ];
        System.assertEquals('Completed', updatedTask.Status);
    }

    @isTest
    static void rejectsDoctorFromAnotherDepartment() {
        Department__c admissionDepartment = new Department__c(
            Name = 'Admission Department Reject Test',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        Department__c doctorDepartment = new Department__c(
            Name = 'Other Doctor Department Reject Test',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert new List<Department__c>{ admissionDepartment, doctorDepartment };

        Test.setMock(HttpCalloutMock.class, new EmergencyMock());
        Patient__c patient = new Patient__c(
            Name = 'Reject Patient',
            Phone__c = '9000000002'
        );
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Patient_Name__c = 'Reject Patient',
            Phone__c = '9000000002',
            Department__c = admissionDepartment.Id,
            Admission_Type__c = 'Emergency'
        );
        insert admission;

        Task escalationTask = new Task(
            WhatId = admission.Id,
            Subject = 'Emergency admission pending doctor assignment: ' + admission.Name,
            Priority = 'High',
            Status = 'Not Started',
            ActivityDate = Date.today()
        );
        insert escalationTask;

        Doctor__c wrongDoctor = new Doctor__c(
            Name = 'Wrong Department Assignment Doctor',
            Department__c = doctorDepartment.Id
        );
        insert wrongDoctor;

        try {
            EmergencyTaskDoctorAssignmentController.assignDoctor(escalationTask.Id, wrongDoctor.Id);
            System.assert(false, 'Cross-department assignment should fail.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
    }
}
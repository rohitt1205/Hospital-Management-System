@IsTest
private class AdmissionAgentActionsTest {
    @TestSetup
    static void setupData() {
        Department__c department = new Department__c(
            Name = 'Agent Test Cardiology',
            Is_Medical_Department__c = true
        );
        insert department;

        Doctor__c doctor = new Doctor__c(
            Name = 'Dr Agent Test',
            Department__c = department.Id,
            Availability_Status__c = 'Available',
            Active__c = true
        );
        insert doctor;

        Patient__c patient = new Patient__c(
            Name = 'Agent Test Patient',
            Blood_Group__c = 'O+',
            Status__c = 'Active'
        );
        insert patient;
    }

    @IsTest
    static void findsPatientAndDoctorByNames() {
        Patient__c patient = [
            SELECT Id, Patient_ID__c
            FROM Patient__c
            WHERE Name = 'Agent Test Patient'
        ];

        FindPatientAction.Request patientRequest =
            new FindPatientAction.Request();
        patientRequest.patientId = patient.Patient_ID__c;

        List<FindPatientAction.Response> patientResponses =
            FindPatientAction.findPatient(
                new List<FindPatientAction.Request>{ patientRequest }
            );

        System.assertEquals(true, patientResponses[0].patientFound);
        System.assertNotEquals(null, patientResponses[0].patientRecordId);

        GetAvailableDoctorAction.Request doctorRequest =
            new GetAvailableDoctorAction.Request();
        doctorRequest.departmentId = 'Agent Test Cardiology';

        List<GetAvailableDoctorAction.Response> doctorResponses =
            GetAvailableDoctorAction.getDoctor(
                new List<GetAvailableDoctorAction.Request>{ doctorRequest }
            );

        System.assertEquals(true, doctorResponses[0].doctorFound);
        System.assertEquals('Dr Agent Test', doctorResponses[0].doctorName);
    }

    @IsTest
    static void createsAdmissionAndReturnsRecordUrl() {
        Patient__c patient = [
            SELECT Id
            FROM Patient__c
            WHERE Name = 'Agent Test Patient'
        ];

        CreateAdmissionAction.Request requestValue =
            new CreateAdmissionAction.Request();
        requestValue.patientId = patient.Id;
        requestValue.admissionType = 'Planned';
        requestValue.symptoms = 'Test symptoms';
        requestValue.departmentId = 'Agent Test Cardiology';
        requestValue.doctorId = 'Dr Agent Test';

        Test.startTest();
        List<CreateAdmissionAction.Response> responses =
            CreateAdmissionAction.createAdmission(
                new List<CreateAdmissionAction.Request>{ requestValue }
            );
        Test.stopTest();

        System.assertEquals(true, responses[0].success, responses[0].message);
        System.assertNotEquals(null, responses[0].admissionId);
        System.assert(responses[0].recordUrl.contains(
            '/lightning/r/Admission__c/'
        ));
        System.assert(responses[0].message.contains(responses[0].recordUrl));

        Admission__c createdAdmission = [
            SELECT Blood_Group__c
            FROM Admission__c
            WHERE Id = :responses[0].admissionId
        ];
        System.assertEquals('O+', createdAdmission.Blood_Group__c);
    }

    @IsTest
    static void rejectsInvalidBloodGroup() {
        Patient__c patient = [
            SELECT Id
            FROM Patient__c
            WHERE Name = 'Agent Test Patient'
        ];

        CreateAdmissionAction.Request requestValue =
            new CreateAdmissionAction.Request();
        requestValue.patientId = patient.Id;
        requestValue.bloodGroup = 'INVALID';
        requestValue.admissionType = 'Planned';
        requestValue.departmentId = 'Agent Test Cardiology';
        requestValue.doctorId = 'Dr Agent Test';

        List<CreateAdmissionAction.Response> responses =
            CreateAdmissionAction.createAdmission(
                new List<CreateAdmissionAction.Request>{ requestValue }
            );

        System.assertEquals(false, responses[0].success);
        System.assert(responses[0].message.contains('valid blood group'));
    }

    @IsTest
    static void searchesAdmissionByNumberAndPatientName() {
        Patient__c patient = [
            SELECT Id
            FROM Patient__c
            WHERE Name = 'Agent Test Patient'
        ];
        Department__c department = [
            SELECT Id
            FROM Department__c
            WHERE Name = 'Agent Test Cardiology'
        ];
        Doctor__c doctor = [
            SELECT Id
            FROM Doctor__c
            WHERE Name = 'Dr Agent Test'
        ];

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Department__c = department.Id,
            Doctor__c = doctor.Id,
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Draft',
            Approval_Status__c = 'Pending Approval'
        );
        insert admission;

        admission = [
            SELECT Id, Name
            FROM Admission__c
            WHERE Id = :admission.Id
        ];

        SearchAdmissionAction.Request numberRequest =
            new SearchAdmissionAction.Request();
        numberRequest.searchText = admission.Name;

        List<SearchAdmissionAction.Response> numberResponses =
            SearchAdmissionAction.searchAdmissions(
                new List<SearchAdmissionAction.Request>{ numberRequest }
            );

        System.assertEquals(true, numberResponses[0].admissionFound);
        System.assertEquals(1, numberResponses[0].resultCount);
        System.assert(numberResponses[0].recordUrl.contains(
            '/lightning/r/Admission__c/'
        ));

        SearchAdmissionAction.Request nameRequest =
            new SearchAdmissionAction.Request();
        nameRequest.searchText = 'Agent Test Patient';

        List<SearchAdmissionAction.Response> nameResponses =
            SearchAdmissionAction.searchAdmissions(
                new List<SearchAdmissionAction.Request>{ nameRequest }
            );

        System.assertEquals(true, nameResponses[0].admissionFound);
        System.assert(nameResponses[0].resultCount > 0);
        System.assert(nameResponses[0].admissionDetails.contains(admission.Name));
    }
}
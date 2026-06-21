@isTest
private class FinalReportUniquenessTest {
    private class CalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"success":true}');
            return response;
        }
    }

    private class TestData {
        Department__c department;
        Doctor__c doctor;
        Patient__c patient;
    }

    private static TestData createTestData(String suffix) {
        TestData data = new TestData();
        data.department = new Department__c(
            Name = 'Report Department ' + suffix,
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert data.department;

        data.doctor = new Doctor__c(
            Name = 'Report Doctor ' + suffix,
            Specialization__c = 'General Medicine',
            Department__c = data.department.Id
        );
        insert data.doctor;

        data.patient = new Patient__c(
            Name = 'Report Patient ' + suffix,
            Phone__c = '9910154408',
            Status__c = 'Active'
        );
        insert data.patient;
        return data;
    }

    @isTest
    static void rejectsDuplicateForAdmissionCreatedFromAppointment() {
        Test.setMock(HttpCalloutMock.class, new CalloutMock());
        TestData data = createTestData('Appointment');

        Appointment__c appointment = new Appointment__c(
            Patient__c = data.patient.Id,
            Doctor__c = data.doctor.Id,
            Department__c = data.department.Id,
            Appointment_Date_Time__c = System.now().addHours(1),
            Appointment_Date__c = Date.today().addDays(1),
            Appointment_Time__c = '10:00',
            Status__c = 'Confirmed'
        );
        insert appointment;

        Admission__c admission = new Admission__c(
            Appointment__c = appointment.Id,
            Patient__c = data.patient.Id,
            Doctor__c = data.doctor.Id,
            Department__c = data.department.Id,
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Admitted'
        );
        insert admission;

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Final_Report__c WHERE Admission__c = :admission.Id]
        );

        Database.SaveResult result = Database.insert(
            new Final_Report__c(
                Admission__c = admission.Id,
                Patient__c = data.patient.Id,
                Doctor__c = data.doctor.Id,
                Status__c = 'Draft'
            ),
            false
        );

        System.assertEquals(false, result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('already exists for this Admission'));
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Final_Report__c WHERE Admission__c = :admission.Id]
        );
    }

    @isTest
    static void rejectsDuplicatesWithinSameInsertBatch() {
        Test.setMock(HttpCalloutMock.class, new CalloutMock());
        TestData data = createTestData('Bulk');

        Admission__c admission = new Admission__c(
            Patient__c = data.patient.Id,
            Doctor__c = data.doctor.Id,
            Department__c = data.department.Id,
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Admitted'
        );
        insert admission;

        delete [SELECT Id FROM Final_Report__c WHERE Admission__c = :admission.Id];

        Final_Report__c firstReport = new Final_Report__c(
            Admission__c = admission.Id,
            Status__c = 'Draft'
        );
        Final_Report__c secondReport = new Final_Report__c(
            Admission__c = admission.Id,
            Status__c = 'Draft'
        );

        Database.SaveResult[] results = Database.insert(
            new List<Final_Report__c>{ firstReport, secondReport },
            false
        );

        System.assertEquals(false, results[0].isSuccess());
        System.assertEquals(false, results[1].isSuccess());
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Final_Report__c WHERE Admission__c = :admission.Id]
        );
    }
}
@isTest
private class PatientAdmissionHandlerTest {

    private class PatientAdmissionMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void testReleaseBedAllocationOnDischarge() {
        Test.setMock(HttpCalloutMock.class, new PatientAdmissionMock());

        // Create Patient
        Patient__c patient = new Patient__c(
            Name = 'Test Discharge Patient', 
            Status__c = 'Active',
            Phone__c = '9876543210'
        );
        insert patient;

        // Create Ward
        Ward__c ward = new Ward__c(
            Name = 'General',
            Ward_Type__c = 'General', 
            Capacity__c = 10
        );
        insert ward;

        // Create Room
        Room__c room = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 2,
            Occupied_Beds__c = 0
        );
        insert room;

        // Create Admission
        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Patient_Name__c = patient.Name,
            Phone__c = '9876543210',
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now().addMinutes(-60),
            Status__c = 'Admitted',
            Room__c = room.Id
        );
        insert admission;

        // Create Bed Allocation
        Bed_Allocation__c allocation = new Bed_Allocation__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Room__c = room.Id,
            Bed_Number__c = '1',
            Start_Date_Time__c = System.now().addMinutes(-30),
            Status__c = 'Occupied'
        );
        insert allocation;

        for (Invoice__c invoice : [
            SELECT Id, Payment_Status__c, Status__c
            FROM Invoice__c
            WHERE Admission__c = :admission.Id
        ]) {
            invoice.Payment_Status__c = 'Paid';
            invoice.Status__c = 'Paid';
            update invoice;
        }

        // Verify occupied count is updated
        room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
        System.assertEquals(1, room.Occupied_Beds__c, 'Room should have 1 occupied bed');
        System.assertEquals(1, room.Available_Beds__c, 'Room should have 1 available bed');

        // Discharge the patient
        Test.startTest();
        admission.Status__c = 'Discharged';
        admission.Actual_Discharge_Date_Time__c = System.now();
        update admission;
        Test.stopTest();

        // Verify the Bed Allocation is released
        Bed_Allocation__c updatedAllocation = [
            SELECT Id, Status__c, End_Date_Time__c 
            FROM Bed_Allocation__c 
            WHERE Id = :allocation.Id
        ];
        System.assertEquals('Released', updatedAllocation.Status__c, 'Bed allocation should be released');
        System.assertNotEquals(null, updatedAllocation.End_Date_Time__c, 'End Date/Time should be populated');

        // Verify occupied count and available count are updated
        room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
        System.assertEquals(0, room.Occupied_Beds__c, 'Room should have 0 occupied beds');
        System.assertEquals(2, room.Available_Beds__c, 'Room should have 2 available beds');
    }

    @isTest
    static void testPendingPaymentMovesDischargeToPending() {
        Test.setMock(HttpCalloutMock.class, new PatientAdmissionMock());

        Patient__c patient = new Patient__c(
            Name = 'Pending Payment Patient',
            Status__c = 'Active',
            Phone__c = '9876543211'
        );
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Patient_Name__c = patient.Name,
            Phone__c = patient.Phone__c,
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now().addHours(-1),
            Status__c = 'Admitted'
        );
        insert admission;

        Invoice__c invoice = [
            SELECT Id, Payment_Status__c, Net_Payable__c
            FROM Invoice__c
            WHERE Admission__c = :admission.Id
            LIMIT 1
        ];
        if (invoice.Net_Payable__c == null || invoice.Net_Payable__c <= 0) {
            invoice.Gross_Amount__c = 500;
            invoice.Net_Payable__c = 500;
            invoice.Payment_Status__c = 'Unpaid';
            update invoice;
        }

        Test.startTest();
        admission.Status__c = 'Discharged';
        admission.Actual_Discharge_Date_Time__c = System.now();
        update admission;
        Test.stopTest();

        admission = [
            SELECT Status__c, Actual_Discharge_Date_Time__c
            FROM Admission__c
            WHERE Id = :admission.Id
        ];
        System.assertEquals('Pending Discharge', admission.Status__c);
        System.assertEquals(null, admission.Actual_Discharge_Date_Time__c);
    }

    @isTest
    static void testAdmissionWithInsuranceCompanyRequiresPolicyNumberOnInsert() {
        Test.setMock(HttpCalloutMock.class, new PatientAdmissionMock());

        Patient__c patient = new Patient__c(Name = 'Test Ins Pat', Patient_Category__c = 'Normal', Phone__c = '9876543210');
        insert patient;

        Insurance_Company__c company = new Insurance_Company__c(Name = 'InsCorp', Active__c = true);
        insert company;

        Ward__c ward = new Ward__c(Ward_Type__c = 'General', Capacity__c = 10);
        insert ward;

        Room__c room = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 10
        );
        insert room;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Ward__c = ward.Id,
            Room__c = room.Id,
            Admission_Date_Time__c = DateTime.now(),
            Status__c = 'Draft',
            Phone__c = '9876543210',
            Insurance_Company__c = company.Id,
            Insurance_Policy_Number__c = null // Left empty to trigger validation
        );

        Test.startTest();
        try {
            insert admission;
            System.assert(false, 'Expected Admission insert to fail due to missing policy number.');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Insurance Policy Number cannot be empty'), 
                'Expected insurance validation message, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testAdmissionWithInsuranceCompanyRequiresPolicyNumberOnUpdate() {
        Test.setMock(HttpCalloutMock.class, new PatientAdmissionMock());

        Patient__c patient = new Patient__c(Name = 'Test Ins Pat 2', Patient_Category__c = 'Normal', Phone__c = '9876543210');
        insert patient;

        Insurance_Company__c company = new Insurance_Company__c(Name = 'InsCorp 2', Active__c = true);
        insert company;

        Ward__c ward = new Ward__c(Ward_Type__c = 'General', Capacity__c = 10);
        insert ward;

        Room__c room = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 10
        );
        insert room;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Ward__c = ward.Id,
            Room__c = room.Id,
            Phone__c = '9876543210',
            Admission_Date_Time__c = DateTime.now(),
            Status__c = 'Draft'
        );
        insert admission;

        admission.Insurance_Company__c = company.Id;
        admission.Insurance_Policy_Number__c = ''; // Empty string triggers validation

        Test.startTest();
        try {
            update admission;
            System.assert(false, 'Expected Admission update to fail due to missing policy number.');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Insurance Policy Number cannot be empty'), 
                'Expected insurance validation message, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testAdmissionWithInsuranceAndPolicyNumberSucceeds() {
        Test.setMock(HttpCalloutMock.class, new PatientAdmissionMock());

        Patient__c patient = new Patient__c(Name = 'Test Ins Pat 3', Patient_Category__c = 'Normal', Phone__c = '9876543210');
        insert patient;

        Insurance_Company__c company = new Insurance_Company__c(Name = 'InsCorp 3', Active__c = true);
        insert company;

        Ward__c ward = new Ward__c(Ward_Type__c = 'General', Capacity__c = 10);
        insert ward;

        Room__c room = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 10
        );
        insert room;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Ward__c = ward.Id,
            Room__c = room.Id,
            Admission_Date_Time__c = DateTime.now(),
            Status__c = 'Draft',
            Phone__c = '9876543210',
            Insurance_Company__c = company.Id,
            Insurance_Policy_Number__c = 'POL-SUCCESS-123'
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(admission, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Admission with company and policy number should succeed.');
    }
}
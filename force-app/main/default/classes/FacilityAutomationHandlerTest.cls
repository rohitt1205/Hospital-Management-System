@isTest
private class FacilityAutomationHandlerTest {
    private class FacilityMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void releasedPatientAllocationIsNotRelinkedToNewAdmission() {
        Test.setMock(HttpCalloutMock.class, new FacilityMock());
        Patient__c patient = new Patient__c(Name = 'Released Allocation Patient', Status__c = 'Active', Phone__c = '9876543210');
        insert patient;

        Ward__c ward = new Ward__c(Name = 'General', Ward_Type__c = 'General', Capacity__c = 10);
        insert ward;

        Room__c room = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 20,
            Occupied_Beds__c = 0
        );
        insert room;

        Bed_Allocation__c releasedAllocation = new Bed_Allocation__c(
            Patient__c = patient.Id,
            Room__c = room.Id,
            Bed_Number__c = '1',
            Start_Date_Time__c = System.now().addDays(-1),
            Status__c = 'Released'
        );
        insert releasedAllocation;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Patient_Name__c = patient.Name,
            Phone__c = '7777777777',
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Draft'
        );
        insert admission;

        Test.startTest();
        releasedAllocation = [
            SELECT Id, Admission__c
            FROM Bed_Allocation__c
            WHERE Id = :releasedAllocation.Id
        ];
        releasedAllocation.Status__c = 'Released';
        update releasedAllocation;
        Test.stopTest();

        Bed_Allocation__c savedAllocation = [
            SELECT Admission__c
            FROM Bed_Allocation__c
            WHERE Id = :releasedAllocation.Id
        ];
        System.assertEquals(null, savedAllocation.Admission__c, 'Released historical allocations should not be linked to a new/latest admission.');
    }

    @isTest
    static void activeAllocationCannotStartBeforeAdmission() {
        Test.setMock(HttpCalloutMock.class, new FacilityMock());
        Patient__c patient = new Patient__c(Name = 'Active Allocation Patient', Status__c = 'Active', Phone__c = '9876543210');
        insert patient;

        Ward__c ward = new Ward__c(Name = 'General', Ward_Type__c = 'General', Capacity__c = 10);
        insert ward;

        Room__c room = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 20,
            Occupied_Beds__c = 0
        );
        insert room;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Patient_Name__c = patient.Name,
            Phone__c = '6666666666',
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Draft'
        );
        insert admission;

        Bed_Allocation__c allocation = new Bed_Allocation__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Room__c = room.Id,
            Bed_Number__c = '2',
            Start_Date_Time__c = System.now().addHours(-1),
            Status__c = 'Reserved'
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(allocation, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Active allocation before admission should be blocked.');
        System.assert(
            result.getErrors()[0].getMessage().contains('Bed allocation start date and time cannot be before the patient admission date and time.'),
            'Expected the admission date consistency error.'
        );
    }

    @isTest
    static void bedNumberRemainsLockedUntilAllocationIsReleased() {
        Test.setMock(HttpCalloutMock.class, new FacilityMock());
        Patient__c firstPatient = new Patient__c(Name = 'First Bed Patient', Status__c = 'Active', Phone__c = '9876543210');
        Patient__c secondPatient = new Patient__c(Name = 'Second Bed Patient', Status__c = 'Active', Phone__c = '9876543210');
        insert new List<Patient__c>{ firstPatient, secondPatient };

        Ward__c ward = new Ward__c(Name = 'Lock Test Ward', Ward_Type__c = 'General', Capacity__c = 10);
        insert ward;

        Room__c room = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 20,
            Occupied_Beds__c = 0
        );
        insert room;

        Admission__c firstAdmission = new Admission__c(
            Patient__c = firstPatient.Id,
            Patient_Name__c = firstPatient.Name,
            Phone__c = '9000000001',
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Draft'
        );
        Admission__c secondAdmission = new Admission__c(
            Patient__c = secondPatient.Id,
            Patient_Name__c = secondPatient.Name,
            Phone__c = '9000000002',
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Draft'
        );
        insert new List<Admission__c>{ firstAdmission, secondAdmission };

        Bed_Allocation__c firstAllocation = new Bed_Allocation__c(
            Patient__c = firstPatient.Id,
            Admission__c = firstAdmission.Id,
            Room__c = room.Id,
            Bed_Number__c = '1',
            Start_Date_Time__c = System.now(),
            End_Date_Time__c = System.now().addDays(1),
            Status__c = 'Occupied'
        );
        insert firstAllocation;

        Bed_Allocation__c duplicateAllocation = new Bed_Allocation__c(
            Patient__c = secondPatient.Id,
            Admission__c = secondAdmission.Id,
            Room__c = room.Id,
            Bed_Number__c = '1',
            Start_Date_Time__c = System.now(),
            Status__c = 'Reserved'
        );

        Test.startTest();
        Database.SaveResult blockedResult = Database.insert(duplicateAllocation, false);
        Test.stopTest();

        System.assertEquals(false, blockedResult.isSuccess(), 'An occupied bed must remain locked until release.');
        System.assert(
            blockedResult.getErrors()[0].getMessage().contains('already allocated'),
            'Expected the duplicate bed allocation error.'
        );

        firstAllocation.Status__c = 'Released';
        update firstAllocation;

        insert duplicateAllocation;
        System.assertNotEquals(null, duplicateAllocation.Id, 'The same bed should be reusable after release.');

        room = [
            SELECT Capacity__c, Occupied_Beds__c, Available_Beds__c
            FROM Room__c
            WHERE Id = :room.Id
        ];
        System.assertEquals(1, room.Occupied_Beds__c, 'Only the new allocation should be occupied.');
        System.assertEquals(19, room.Available_Beds__c, 'Available beds should remain consistent after release and reuse.');
    }

    @isTest
    static void patientCannotHoldTwoActiveBedsAcrossRooms() {
        Test.setMock(HttpCalloutMock.class, new FacilityMock());
        Patient__c patient = new Patient__c(Name = 'Single Active Bed Patient', Status__c = 'Active', Phone__c = '9876543210');
        insert patient;

        Ward__c ward = new Ward__c(Name = 'Patient Lock Ward', Ward_Type__c = 'General', Capacity__c = 10);
        insert ward;
        Room__c firstRoom = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 20,
            Occupied_Beds__c = 0
        );
        Room__c secondRoom = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'private non ac room without extra bed',
            Capacity__c = 20,
            Occupied_Beds__c = 0
        );
        insert new List<Room__c>{ firstRoom, secondRoom };

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Patient_Name__c = patient.Name,
            Phone__c = '9000000020',
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Draft'
        );
        insert admission;

        Bed_Allocation__c currentAllocation = new Bed_Allocation__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Room__c = firstRoom.Id,
            Bed_Number__c = '1',
            Start_Date_Time__c = System.now(),
            Status__c = 'Occupied'
        );
        insert currentAllocation;

        Bed_Allocation__c secondAllocation = new Bed_Allocation__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Room__c = secondRoom.Id,
            Bed_Number__c = '1',
            Start_Date_Time__c = System.now(),
            Status__c = 'Reserved'
        );

        Test.startTest();
        Database.SaveResult blockedResult = Database.insert(secondAllocation, false);
        Test.stopTest();

        System.assertEquals(false, blockedResult.isSuccess());
        System.assert(
            blockedResult.getErrors()[0].getMessage().contains('already has an active bed allocation'),
            'Expected the patient-level active bed error.'
        );

        currentAllocation.Status__c = 'Released';
        update currentAllocation;
        insert secondAllocation;
        System.assertNotEquals(null, secondAllocation.Id, 'A new bed should be allowed after release.');
    }
}
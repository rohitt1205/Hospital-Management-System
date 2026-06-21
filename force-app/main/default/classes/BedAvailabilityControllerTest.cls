@isTest
private class BedAvailabilityControllerTest {
    @isTest
    static void returnsOnlyBedsNotActivelyAllocated() {
        Ward__c ward = new Ward__c(Name = 'Picker Test Ward', Ward_Type__c = 'General', Capacity__c = 10);
        insert ward;
        Room__c room = new Room__c(
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Capacity__c = 3,
            Occupied_Beds__c = 0
        );
        insert room;

        Patient__c patient = new Patient__c(Name = 'Picker Test Patient', Status__c = 'Active');
        insert patient;
        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Patient_Name__c = patient.Name,
            Phone__c = '9000000010',
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Draft'
        );
        insert admission;

        insert new Bed_Allocation__c(
            Patient__c = patient.Id,
            Admission__c = admission.Id,
            Room__c = room.Id,
            Bed_Number__c = '1',
            Start_Date_Time__c = System.now(),
            Status__c = 'Occupied'
        );
        insert new Bed_Allocation__c(
            Patient__c = patient.Id,
            Room__c = room.Id,
            Bed_Number__c = '2',
            Start_Date_Time__c = System.now(),
            Status__c = 'Released'
        );

        Test.startTest();
        List<BedAvailabilityController.BedOption> options =
            BedAvailabilityController.getAvailableBeds(room.Id, null);
        Test.stopTest();

        System.assertEquals(2, options.size());
        System.assertEquals('2', options[0].value);
        System.assertEquals('3', options[1].value);
    }
}
Savepoint sp = Database.setSavepoint();
try {
    Department__c dept = new Department__c(Name = 'Automation Verify Dept');
    insert dept;

    Ward__c ward = new Ward__c(Department__c = dept.Id, Capacity__c = 5, Ward_Type__c = 'General');
    insert ward;

    Room__c room = new Room__c(Name = 'VERIFY-ROOM-1', Ward__c = ward.Id, Room_Type__c = 'private ac room without extra bed', Capacity__c = 2);
    insert room;
    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c, Price__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(0, Integer.valueOf(room.Occupied_Beds__c), 'Room should start with zero occupied beds.');
    System.assertEquals(2, Integer.valueOf(room.Available_Beds__c), 'Room should start with all beds available.');

    Patient__c patient = new Patient__c(Name = 'Allocation Verify Patient', Patient_Category__c = 'Normal');
    insert patient;

    Bed_Allocation__c allocation = new Bed_Allocation__c(
        Room__c = room.Id,
        Patient__c = patient.Id,
        Bed_Number__c = '1',
        Status__c = 'Occupied',
        Ward_Manager_Approval__c = 'Approved'
    );
    insert allocation;

    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(1, Integer.valueOf(room.Occupied_Beds__c), 'Occupied beds should increase after active allocation.');
    System.assertEquals(1, Integer.valueOf(room.Available_Beds__c), 'Available beds should decrease after active allocation.');

    allocation.Status__c = 'Released';
    allocation.End_Date_Time__c = System.now();
    update allocation;

    room = [SELECT Id, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(0, Integer.valueOf(room.Occupied_Beds__c), 'Occupied beds should return to zero after release.');
    System.assertEquals(2, Integer.valueOf(room.Available_Beds__c), 'Available beds should return after release.');

    System.debug('ROOM_ALLOCATION_AUTOMATION_OK');
} finally {
    Database.rollback(sp);
}

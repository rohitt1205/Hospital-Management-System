Savepoint sp = Database.setSavepoint();
try {
    Department__c dept = new Department__c(Name = 'Capacity Delta Verify Dept');
    insert dept;
    Ward__c ward = new Ward__c(Department__c = dept.Id, Ward_Type__c = 'General', Capacity__c = 5);
    insert ward;

    Room__c room = new Room__c(
        Name = 'CAPACITY-DELTA-VERIFY',
        Ward__c = ward.Id,
        Room_Type__c = 'private ac room with extra bed',
        Capacity__c = 2
    );
    insert room;
    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c, Price__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(2, Integer.valueOf(room.Capacity__c), 'Initial available capacity should be 2.');
    System.assertEquals(0, Integer.valueOf(room.Occupied_Beds__c), 'Initial occupied beds should be 0.');
    System.assertEquals(2, Integer.valueOf(room.Available_Beds__c), 'Available Beds should mirror capacity.');

    Patient__c patient = new Patient__c(Name = 'Capacity Delta Verify Patient', Patient_Category__c = 'Normal');
    insert patient;

    Bed_Allocation__c allocation = new Bed_Allocation__c(
        Room__c = room.Id,
        Patient__c = patient.Id,
        Bed_Number__c = '1',
        Status__c = 'Occupied'
    );
    insert allocation;

    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(1, Integer.valueOf(room.Capacity__c), 'Capacity should decrease by 1 after allocation.');
    System.assertEquals(1, Integer.valueOf(room.Occupied_Beds__c), 'Occupied beds should increase by 1 after allocation.');
    System.assertEquals(1, Integer.valueOf(room.Available_Beds__c), 'Available Beds should match decreased capacity.');

    allocation.Status__c = 'Released';
    allocation.End_Date_Time__c = System.now();
    update allocation;

    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(2, Integer.valueOf(room.Capacity__c), 'Capacity should increase by 1 after release.');
    System.assertEquals(0, Integer.valueOf(room.Occupied_Beds__c), 'Occupied beds should decrease by 1 after release.');
    System.assertEquals(2, Integer.valueOf(room.Available_Beds__c), 'Available Beds should match restored capacity.');

    System.debug('ROOM_CAPACITY_OCCUPIED_DELTA_OK');
} finally {
    Database.rollback(sp);
}

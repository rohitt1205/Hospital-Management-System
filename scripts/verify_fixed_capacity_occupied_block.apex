Savepoint sp = Database.setSavepoint();
try {
    Department__c dept = new Department__c(Name = 'Fixed Capacity Verify Dept');
    insert dept;
    Ward__c ward = new Ward__c(Department__c = dept.Id, Ward_Type__c = 'General', Capacity__c = 5);
    insert ward;

    Room__c room = new Room__c(
        Name = 'FIXED-CAPACITY-VERIFY',
        Ward__c = ward.Id,
        Room_Type__c = 'private ac room with extra bed',
        Capacity__c = 1
    );
    insert room;
    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(1, Integer.valueOf(room.Capacity__c), 'Capacity should start as total bed capacity.');
    System.assertEquals(0, Integer.valueOf(room.Occupied_Beds__c), 'Occupied should start at zero.');
    System.assertEquals(1, Integer.valueOf(room.Available_Beds__c), 'Available should be capacity minus occupied.');

    Patient__c patientOne = new Patient__c(Name = 'Fixed Capacity Patient 1', Patient_Category__c = 'Normal');
    Patient__c patientTwo = new Patient__c(Name = 'Fixed Capacity Patient 2', Patient_Category__c = 'Normal');
    insert new List<Patient__c>{ patientOne, patientTwo };

    Bed_Allocation__c firstAllocation = new Bed_Allocation__c(
        Room__c = room.Id,
        Patient__c = patientOne.Id,
        Bed_Number__c = '1',
        Status__c = 'Occupied'
    );
    insert firstAllocation;

    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(1, Integer.valueOf(room.Capacity__c), 'Capacity must not decrease after allocation.');
    System.assertEquals(1, Integer.valueOf(room.Occupied_Beds__c), 'Occupied should increase after allocation.');
    System.assertEquals(0, Integer.valueOf(room.Available_Beds__c), 'Available should become zero when full.');

    Boolean blocked = false;
    try {
        insert new Bed_Allocation__c(
            Room__c = room.Id,
            Patient__c = patientTwo.Id,
            Bed_Number__c = '2',
            Status__c = 'Occupied'
        );
    } catch (DmlException ex) {
        blocked = ex.getMessage().contains('Room capacity is full');
    }
    System.assertEquals(true, blocked, 'Second allocation must be blocked when occupied equals capacity.');

    firstAllocation.Status__c = 'Released';
    firstAllocation.End_Date_Time__c = System.now();
    update firstAllocation;

    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(1, Integer.valueOf(room.Capacity__c), 'Capacity must stay fixed after release.');
    System.assertEquals(0, Integer.valueOf(room.Occupied_Beds__c), 'Occupied should decrease after release.');
    System.assertEquals(1, Integer.valueOf(room.Available_Beds__c), 'Available should restore after release.');

    System.debug('FIXED_CAPACITY_OCCUPIED_BLOCK_OK');
} finally {
    Database.rollback(sp);
}

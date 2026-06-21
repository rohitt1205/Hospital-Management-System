Savepoint sp = Database.setSavepoint();
try {
    Department__c dept = new Department__c(Name = 'Bed Number Verify Dept');
    insert dept;
    Ward__c ward = new Ward__c(Department__c = dept.Id, Ward_Type__c = 'General', Capacity__c = 5);
    insert ward;

    Room__c room = new Room__c(
        Name = 'BED-NUMBER-VERIFY',
        Ward__c = ward.Id,
        Room_Type__c = 'private ac room with extra bed',
        Capacity__c = 2
    );
    insert room;
    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(2, Integer.valueOf(room.Capacity__c), 'Capacity should be 2.');
    System.assertEquals(0, Integer.valueOf(room.Occupied_Beds__c), 'Occupied should start at 0.');
    System.assertEquals(2, Integer.valueOf(room.Available_Beds__c), 'Available should equal capacity when room is created.');

    Patient__c patientOne = new Patient__c(Name = 'Bed Number Patient 1', Patient_Category__c = 'Normal');
    Patient__c patientTwo = new Patient__c(Name = 'Bed Number Patient 2', Patient_Category__c = 'Normal');
    insert new List<Patient__c>{ patientOne, patientTwo };

    Boolean bedNumberBlocked = false;
    try {
        insert new Bed_Allocation__c(
            Room__c = room.Id,
            Patient__c = patientOne.Id,
            Bed_Number__c = '3',
            Status__c = 'Occupied'
        );
    } catch (DmlException ex) {
        bedNumberBlocked = ex.getMessage().contains('Bed number cannot be greater than the room bed capacity');
    }
    System.assertEquals(true, bedNumberBlocked, 'Bed number greater than capacity must be blocked.');

    Bed_Allocation__c allocation = new Bed_Allocation__c(
        Room__c = room.Id,
        Patient__c = patientTwo.Id,
        Bed_Number__c = '2',
        Status__c = 'Occupied'
    );
    insert allocation;

    room = [SELECT Id, Capacity__c, Occupied_Beds__c, Available_Beds__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(2, Integer.valueOf(room.Capacity__c), 'Capacity should stay fixed after allocation.');
    System.assertEquals(1, Integer.valueOf(room.Occupied_Beds__c), 'Occupied should increase after allocation.');
    System.assertEquals(1, Integer.valueOf(room.Available_Beds__c), 'Available should reduce after allocation.');

    System.debug('AVAILABLE_AND_BED_NUMBER_VALIDATION_OK');
} finally {
    Database.rollback(sp);
}

Savepoint sp = Database.setSavepoint();
try {
    Department__c dept = new Department__c(Name = 'Daily Rate Verify Dept');
    insert dept;
    Ward__c ward = new Ward__c(Department__c = dept.Id, Ward_Type__c = 'General', Capacity__c = 5);
    insert ward;

    Room__c room = new Room__c(
        Name = 'DAILY-RATE-VERIFY',
        Ward__c = ward.Id,
        Room_Type__c = 'private ac room with extra bed',
        Capacity__c = 2
    );
    insert room;
    room = [SELECT Id, Price__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(150, room.Price__c, 'Room price should be auto-filled first.');

    Patient__c patient = new Patient__c(Name = 'Daily Rate Verify Patient', Patient_Category__c = 'Normal');
    insert patient;

    Bed_Allocation__c allocation = new Bed_Allocation__c(
        Room__c = room.Id,
        Patient__c = patient.Id,
        Bed_Number__c = '1',
        Status__c = 'Reserved',
        Daily_Rate__c = 999
    );
    insert allocation;

    allocation = [SELECT Id, Daily_Rate__c FROM Bed_Allocation__c WHERE Id = :allocation.Id];
    System.assertEquals(room.Price__c, allocation.Daily_Rate__c, 'Daily Rate must be copied from Room Price on insert.');

    allocation.Daily_Rate__c = 1;
    update allocation;
    allocation = [SELECT Id, Daily_Rate__c FROM Bed_Allocation__c WHERE Id = :allocation.Id];
    System.assertEquals(room.Price__c, allocation.Daily_Rate__c, 'Daily Rate must stay synced from Room Price on update.');

    System.debug('BED_ALLOCATION_DAILY_RATE_SYNC_OK');
} finally {
    Database.rollback(sp);
}

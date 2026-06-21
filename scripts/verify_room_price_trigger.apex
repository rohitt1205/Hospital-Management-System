Savepoint sp = Database.setSavepoint();
try {
    Department__c dept = new Department__c(Name = 'Room Price Verify Dept');
    insert dept;
    Ward__c ward = new Ward__c(Department__c = dept.Id, Ward_Type__c = 'General', Capacity__c = 8);
    insert ward;

    Map<String, Decimal> expectedByType = new Map<String, Decimal>{
        'shared non ac room without extra bed' => 50,
        'Shared Non AC Room with extra bed' => 75,
        'shared ac room without extra bed' => 100,
        'shared Ac room with extra bed' => 125,
        'private non ac room without extra bed' => 100,
        'private ac room without extra bed' => 125,
        'Private non ac room with extra bed' => 125,
        'private ac room with extra bed' => 150
    };

    List<Room__c> rooms = new List<Room__c>();
    Integer idx = 1;
    for (String roomType : expectedByType.keySet()) {
        rooms.add(new Room__c(
            Name = 'PRICE-VERIFY-' + idx,
            Ward__c = ward.Id,
            Room_Type__c = roomType,
            Capacity__c = 2
        ));
        idx++;
    }
    insert rooms;

    for (Room__c room : [SELECT Room_Type__c, Price__c FROM Room__c WHERE Id IN :rooms]) {
        System.assertEquals(expectedByType.get(room.Room_Type__c), room.Price__c, 'Wrong price for ' + room.Room_Type__c);
    }
    System.debug('ROOM_PRICE_TRIGGER_OK');
} finally {
    Database.rollback(sp);
}

Id wardId = 'a0Yg5000004MYyPEAW'; // Ward 'test' with Capacity = 1

try {
    Room__c room = new Room__c(
        Name = '1',
        Ward__c = wardId,
        Room_Type__c = 'Shared',
        Capacity__c = 2
    );
    insert room;
    
    // Query database to check the actual name saved
    Room__c savedRoom = [SELECT Id, Name FROM Room__c WHERE Id = :room.Id];
    System.debug('Succeeded! Room created in database with Name: ' + savedRoom.Name);
} catch (DmlException e) {
    System.debug('Failed: ' + e.getMessage());
}

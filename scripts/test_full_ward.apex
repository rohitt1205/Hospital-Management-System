Id wardId = 'a0Yg5000004MZCvEAO';
// Insert rooms one by one to verify the limit
for (Integer i = 1; i <= 6; i++) {
    try {
        Room__c room = new Room__c(
            Ward__c = wardId,
            Room_Type__c = 'Shared',
            Capacity__c = 2
        );
        insert room;
        System.debug('Successfully inserted room #' + i + ': ' + room.Id);
    } catch (DmlException e) {
        System.debug('Failed to insert room #' + i + '. Error: ' + e.getMessage());
    }
}

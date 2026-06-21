Room__c room = new Room__c();
room.Ward__c = 'a0Yg5000004MZCvEAO'; // Ward 'Test Ward Val' (Capacity = 5, currently has 0 rooms)
room.Room_Type__c = 'Shared';
room.Capacity__c = 2; // Beds Capacity
insert room;
System.debug('Successfully inserted room: ' + room.Id);

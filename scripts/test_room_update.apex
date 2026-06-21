Room__c room = [SELECT Id, Name FROM Room__c WHERE Name = 'GEN016' LIMIT 1];
update room;

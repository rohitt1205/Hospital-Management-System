Admission__c admission = [
    SELECT Id
    FROM Admission__c
    WHERE Name = 'ADM-00050'
    LIMIT 1
];
update new Admission__c(Id = admission.Id);

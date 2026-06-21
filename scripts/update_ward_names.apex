List<Ward__c> wards = [SELECT Id, Name, Ward_Type__c FROM Ward__c WHERE Ward_Type__c != null];
for (Ward__c w : wards) {
    w.Name = w.Ward_Type__c;
}
update wards;
System.debug('All Ward names updated to match Ward Type exactly.');

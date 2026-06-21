List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();

for (Invoice__c invoice : [
    SELECT Id, Insurance_Verified__c, Admission__r.Insurance_Verified__c
    FROM Invoice__c
    WHERE Admission__c != null
]) {
    Boolean admissionVerified = invoice.Admission__r.Insurance_Verified__c;
    if (invoice.Insurance_Verified__c != admissionVerified) {
        invoice.Insurance_Verified__c = admissionVerified;
        invoicesToUpdate.add(invoice);
    }
}

if (!invoicesToUpdate.isEmpty()) {
    update invoicesToUpdate;
}

System.debug('Synced invoice insurance verification count: ' + invoicesToUpdate.size());

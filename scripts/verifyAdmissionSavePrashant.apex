Savepoint sp = Database.setSavepoint();
try {
    Admission__c admission = new Admission__c(
        Patient__c = 'a0Pg5000000ebaLEAQ',
        Patient_Name__c = 'Prashant Joshi',
        Phone__c = '9999999999',
        Admission_Type__c = 'Planned',
        Admission_Date_Time__c = System.now(),
        Status__c = 'Draft'
    );
    insert admission;
    System.debug('HMS_VERIFY_ADMISSION_INSERT_OK=' + admission.Id);
} finally {
    Database.rollback(sp);
}

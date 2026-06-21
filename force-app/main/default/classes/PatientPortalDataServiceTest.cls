@IsTest
private class PatientPortalDataServiceTest {

    @IsTest
    static void loadsAllPatientScopedRecords() {
        Patient__c patient = new Patient__c(
            Name = 'Portal Data Patient',
            Email__c = 'portal.data@test.hms',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId(),
            Date_of_Birth__c = Date.newInstance(1990, 1, 15)
        );
        insert patient;

        insert new Prescription__c(
            Patient__c = patient.Id,
            Status__c = 'Issued',
            Prescription_Date__c = Date.today()
        );
        insert new Invoice__c(
            Patient__c = patient.Id,
            Payment_Status__c = 'Unpaid',
            Net_Payable__c = 500
        );
        insert new Final_Report__c(
            Patient__c = patient.Id,
            Summary__c = 'Discharge summary',
            Status__c = 'Final'
        );
        insert new Insurance_Policy__c(
            Patient__c = patient.Id,
            Plan_Type__c = 'Individual',
            Verification_Status__c = 'Verified'
        );

        Map<String, Object> summary = PatientPortalDataService.baseSummary();
        Test.startTest();
        PatientPortalDataService.enrichSummary(summary, patient);
        Test.stopTest();

        System.assertEquals(1, summary.get('prescriptionCount'));
        System.assertEquals(1, summary.get('invoiceCount'));
        System.assertEquals(1, summary.get('reportCount'));
        System.assertEquals(true, summary.get('hasFinalReport'));
        System.assertEquals(1, summary.get('insuranceCount'));
        System.assertEquals('Portal Data Patient', summary.get('patientName'));
        System.assertNotEquals(null, summary.get('age'));
    }
}
@IsTest
public class PatientTriggerHandlerTest {
    @IsTest
    static void testBiDirectionalStatusSync() {
        Patient__c patient = new Patient__c(
            Name = 'Test Patient Sync',
            Patient_Category__c = 'Normal',
            Phone__c = '9876543210',
            Status__c = 'Active'
        );
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Status__c = 'Draft',
            Phone__c = '9876543210'
        );
        insert admission;

        // Test Admission -> Patient Status sync
        admission.Status__c = 'Admitted';
        update admission;

        Patient__c updatedPatient = [SELECT Status__c FROM Patient__c WHERE Id = :patient.Id];
        System.assertEquals('Admitted', updatedPatient.Status__c, 'Patient status should sync from Admission');

        // Pay invoices to allow Discharge status
        List<Invoice__c> invoices = [SELECT Id, Payment_Status__c FROM Invoice__c WHERE Admission__c = :admission.Id];
        for (Invoice__c inv : invoices) {
            inv.Payment_Status__c = 'Paid';
        }
        if (!invoices.isEmpty()) {
            update invoices;
        }

        // Test Patient -> Admission Status sync
        patient.Status__c = 'Discharged';
        update patient;

        Admission__c updatedAdmission = [SELECT Status__c FROM Admission__c WHERE Id = :admission.Id];
        System.assertEquals('Discharged', updatedAdmission.Status__c, 'Admission status should sync from Patient');
    }
}
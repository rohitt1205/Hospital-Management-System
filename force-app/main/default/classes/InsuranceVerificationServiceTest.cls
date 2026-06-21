@IsTest
public class InsuranceVerificationServiceTest {

    // Mock class for HTTP Callouts
    private class InsuranceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"args": {"policyNumber": "POL12345", "company": "Test Company"}}');
            res.setStatusCode(200);
            return res;
        }
    }

    @IsTest
    static void testStandardDiscountMapping() {
        // Create an Insurance Company
        Insurance_Company__c company = new Insurance_Company__c(
            Name = 'CareCorp',
            Active__c = true,
            Standard_Discount__c = 45.00
        );
        insert company;

        Patient__c patient = new Patient__c(Name = 'Test Patient', Patient_Category__c = 'Normal', Phone__c = '9876543210');
        insert patient;

        // Create Admission
        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now(),
            Insurance_Company__c = company.Id,
            Insurance_Policy_Number__c = 'POL-DISCOUNT',
            Phone__c = '9876543210'
        );

        Test.setMock(HttpCalloutMock.class, new InsuranceMock());

        Test.startTest();
        insert admission;
        Test.stopTest();

        // Verify that standard discount is mapped
        Admission__c queried = [SELECT Insurance_Coverage__c FROM Admission__c WHERE Id = :admission.Id];
        System.assertEquals(45.00, queried.Insurance_Coverage__c, 'Insurance coverage should auto-populate from Standard Discount');
    }

    @IsTest
    static void testSuccessfulVerification() {
        // Create Company
        Insurance_Company__c company = new Insurance_Company__c(
            Name = 'HealthFirst',
            Active__c = true,
            Standard_Discount__c = 50.00
        );
        insert company;

        Patient__c patient = new Patient__c(Name = 'Verified Patient', Patient_Category__c = 'Normal', Phone__c = '9876543210');
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now(),
            Insurance_Company__c = company.Id,
            Insurance_Policy_Number__c = 'POL-VERIFIED-123',
            Phone__c = '9876543210'
        );

        Test.setMock(HttpCalloutMock.class, new InsuranceMock());

        Test.startTest();
        insert admission;
        Test.stopTest();

        // Check if queueable executed and linked policy
        Admission__c updatedAdmission = [
            SELECT Insurance_Verified__c, Insurance_Policy__c 
            FROM Admission__c 
            WHERE Id = :admission.Id
        ];
        System.assertEquals(true, updatedAdmission.Insurance_Verified__c, 'Insurance should be marked as verified');
        System.assertNotEquals(null, updatedAdmission.Insurance_Policy__c, 'Insurance Policy lookup should be populated');

        Insurance_Policy__c policy = [
            SELECT Verification_Status__c, Coverage_Limit__c, Plan_Type__c
            FROM Insurance_Policy__c
            WHERE Id = :updatedAdmission.Insurance_Policy__c
        ];
        System.assertEquals('Verified', policy.Verification_Status__c);
        System.assertEquals(50000.00, policy.Coverage_Limit__c);
    }

    @IsTest
    static void testRejectedAndExpiredVerification() {
        Insurance_Company__c company = new Insurance_Company__c(
            Name = 'HealthFirst',
            Active__c = true,
            Standard_Discount__c = 50.00
        );
        insert company;

        Patient__c patient1 = new Patient__c(Name = 'Rejected Patient', Patient_Category__c = 'Normal', Phone__c = '9876543210');
        Patient__c patient2 = new Patient__c(Name = 'Expired Patient', Patient_Category__c = 'Normal', Phone__c = '9876543210');
        insert new List<Patient__c>{ patient1, patient2 };

        Admission__c admission1 = new Admission__c(
            Patient__c = patient1.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now(),
            Insurance_Company__c = company.Id,
            Insurance_Policy_Number__c = 'POL-REJECTED-123',
            Phone__c = '9876543210'
        );

        Admission__c admission2 = new Admission__c(
            Patient__c = patient2.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now(),
            Insurance_Company__c = company.Id,
            Insurance_Policy_Number__c = 'POL-EXPIRED-123',
            Phone__c = '9876543210'
        );

        Test.setMock(HttpCalloutMock.class, new InsuranceMock());

        Test.startTest();
        insert new List<Admission__c>{ admission1, admission2 };
        Test.stopTest();

        // Check verification flags and lookup
        Admission__c result1 = [SELECT Insurance_Verified__c, Insurance_Policy__c FROM Admission__c WHERE Id = :admission1.Id];
        System.assertEquals(false, result1.Insurance_Verified__c);
        System.assertEquals(null, result1.Insurance_Policy__c);

        Admission__c result2 = [SELECT Insurance_Verified__c, Insurance_Policy__c FROM Admission__c WHERE Id = :admission2.Id];
        System.assertEquals(false, result2.Insurance_Verified__c);
        System.assertEquals(null, result2.Insurance_Policy__c);
    }

    @IsTest
    static void testInvoiceInsuranceDeduction() {
        Insurance_Company__c company = new Insurance_Company__c(
            Name = 'DiscountCorp',
            Active__c = true,
            Standard_Discount__c = 25.00
        );
        insert company;

        Patient__c patient = new Patient__c(Name = 'Billing Patient', Patient_Category__c = 'Normal', Phone__c = '9876543210');
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now(),
            Insurance_Company__c = company.Id,
            Insurance_Policy_Number__c = 'POL-BILLING',
            Phone__c = '9876543210'
        );

        Test.setMock(HttpCalloutMock.class, new InsuranceMock());

        Test.startTest();
        insert admission;
        Test.stopTest();

        // Reload admission to obtain asynchronous updates (e.g. Insurance_Policy__c) from queueable
        admission = [SELECT Id, Patient__c, Status__c, Admission_Date_Time__c, Insurance_Company__c, Insurance_Policy_Number__c, Insurance_Policy__c, Admission_Fee__c FROM Admission__c WHERE Id = :admission.Id];
        // Set up admission charges manually like the billing service does
        InvoiceBillingService.handleAdmissionAfterInsert(new List<Admission__c>{ admission });

        // Retrieve Invoice
        Invoice__c inv = [
            SELECT Id, Gross_Amount__c, Net_Payable__c, Insurance_Covered_Amount__c, Insurance_Policy__c
            FROM Invoice__c
            WHERE Admission__c = :admission.Id
        ];
        
        System.assertNotEquals(null, inv.Insurance_Policy__c, 'Invoice should inherit the insurance policy');

        // Gross should be 500 (admission fee)
        System.assertEquals(500.00, inv.Gross_Amount__c);
        // Covered should be 25% of 500 = 125
        System.assertEquals(125.00, inv.Insurance_Covered_Amount__c);
        // Net payable should be 500 - 125 = 375
        System.assertEquals(375.00, inv.Net_Payable__c);

        // Check that a negative Insurance line item was created
        List<Invoice_Line_Item__c> insuranceLines = [
            SELECT Line_Total__c, Description__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :inv.Id
            AND Charge_Type__c = 'Insurance Deduction'
        ];
        System.assertEquals(1, insuranceLines.size(), 'One Insurance line item should be present');
        System.assertEquals(-125.00, insuranceLines[0].Line_Total__c);
        System.assert(insuranceLines[0].Description__c.contains('25'), 'Description should specify discount percentage');
    }

    @IsTest
    static void testInsurancePolicyNumberRequired() {
        Insurance_Company__c company = new Insurance_Company__c(
            Name = 'CareCorp',
            Active__c = true,
            Standard_Discount__c = 45.00
        );
        insert company;

        Patient__c patient = new Patient__c(Name = 'Test Patient', Patient_Category__c = 'Normal', Phone__c = '9876543210');
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now(),
            Insurance_Company__c = company.Id,
            Phone__c = '9876543210'
        );

        Test.startTest();
        try {
            insert admission;
            System.assert(false, 'Insert should have failed due to missing Insurance Policy Number');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Insurance Policy Number cannot be empty when an Insurance Company is selected'), 
                          'Expected validation error message, but got: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
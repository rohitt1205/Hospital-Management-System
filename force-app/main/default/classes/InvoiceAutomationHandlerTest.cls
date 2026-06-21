@IsTest
private class InvoiceAutomationHandlerTest {
    private class InvoiceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }

    @IsTest
    static void invoiceDefaultsFromAdmissionAndLocksInvoiceDate() {
        Test.setMock(HttpCalloutMock.class, new InvoiceMock());
        Patient__c patient = new Patient__c(
            Name = 'Invoice Automation Patient',
            Patient_Category__c = 'Normal',
            Phone__c = '9876543210'
        );
        insert patient;

        Insurance_Company__c company = new Insurance_Company__c(
            Name = 'Test Insurance Co',
            Standard_Discount__c = 20,
            Active__c = true
        );
        insert company;

        Insurance_Policy__c policy = new Insurance_Policy__c(
            Name = 'Policy-Auto-001',
            Patient__c = patient.Id,
            Insurance_Company__c = company.Id
        );
        insert policy;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Insurance_Policy__c = policy.Id,
            Insurance_Verified__c = true,
            Status__c = 'Admitted',
            Admission_Date_Time__c = Datetime.now(),
            Phone__c = '9876543210'
        );
        insert admission;

        Invoice__c invoice = new Invoice__c(
            Admission__c = admission.Id,
            Patient_Category__c = 'Civil Servant',
            Gross_Amount__c = 1000
        );
        insert invoice;

        invoice = [
            SELECT Patient__c, Insurance_Policy__c, Patient_Category__c, Invoice_Date__c,
                   Payment_Status__c, Discount_Amount__c, Insurance_Covered_Amount__c,
                   Net_Payable__c, Net_Amount__c, Total_Amount__c, Insurance_Verified__c
            FROM Invoice__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(patient.Id, invoice.Patient__c, 'Patient must come from admission.');
        System.assertEquals(policy.Id, invoice.Insurance_Policy__c, 'Insurance policy must come from admission.');
        System.assertEquals(true, invoice.Insurance_Verified__c, 'Insurance verified must come from admission.');
        System.assertEquals('Civil Servant', invoice.Patient_Category__c, 'Invoice patient category must preserve the billing subsidy selection.');
        System.assertEquals(Date.today(), invoice.Invoice_Date__c, 'Invoice date should be system generated as today.');
        System.assertEquals('Unpaid', invoice.Payment_Status__c, 'New invoices should start unpaid.');
        System.assertEquals(400, invoice.Discount_Amount__c, 'Civil Servant subsidy should be 50% after insurance.');
        System.assertEquals(200, invoice.Insurance_Covered_Amount__c, 'Insurance discount should be based on company standard discount.');
        System.assertEquals(400, invoice.Net_Payable__c, 'Net payable should subtract insurance first and subsidy after insurance.');
        System.assertEquals(invoice.Net_Payable__c, invoice.Net_Amount__c);
        System.assertEquals(invoice.Net_Payable__c, invoice.Total_Amount__c);

        invoice.Invoice_Date__c = Date.today().addDays(-1);
        try {
            update invoice;
            System.assert(false, 'Changing invoice date after creation should fail.');
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('Invoice date is system generated and cannot be changed.'),
                'Expected invoice date immutability error. Actual: ' + ex.getMessage()
            );
        }
    }
}
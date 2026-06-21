@isTest
public class HMS_PaymentControllerTest {
    
    // HTTP Callout Mock for Razorpay payment API verification
    private class RazorpayMock implements HttpCalloutMock {
        private Integer statusCode;
        private String statusValue;
        
        public RazorpayMock(Integer statusCode, String statusValue) {
            this.statusCode = statusCode;
            this.statusValue = statusValue;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            
            if (statusCode == 200) {
                if (req.getMethod() == 'POST' && req.getEndpoint().endsWith('/orders')) {
                    res.setBody('{"id":"order_test_12345","status":"created","amount":13800000,"currency":"INR"}');
                } else {
                    res.setBody(
                        '{"id":"pay_test_12345","status":"' + statusValue +
                        '","amount":13800000,"method":"card","order_id":"order_test_12345"}'
                    );
                }
            } else {
                res.setBody('{"error":{"description":"Payment not found"}}');
            }
            return res;
        }
    }
    
    @testSetup
    static void setupTestData() {
        // Create Patient
        Patient__c patient = new Patient__c(
            Name = 'John Doe',
            Gender__c = 'Male',
            Date_of_Birth__c = Date.today().addYears(-30),
            Phone__c = '1234567890',
            Email__c = 'john.doe@example.com',
            Aadhaar_Last_4__c = '1234',
            Status__c = 'Active'
        );
        insert patient;
        
        // Delete any auto-created invoices and payments to ensure our test data is clean
        delete [SELECT Id FROM Invoice__c WHERE Patient__c = :patient.Id];
        delete [SELECT Id FROM Payment__c WHERE Patient__c = :patient.Id];
        
        // Create Invoice
        Invoice__c invoice = new Invoice__c(
            Patient__c = patient.Id,
            Gross_Amount__c = 1500.00,
            Discount_Amount__c = 0.00,
            Insurance_Covered_Amount__c = 0.00,
            Non_Billable_Deduction__c = 0.00,
            Net_Payable__c = 1500.00,
            Payment_Status__c = 'Unpaid',
            Status__c = 'Unpaid'
        );
        insert invoice;
        
        // Create Unpaid Payment record (simulated syncPendingPayments)
        Payment__c payment = new Payment__c(
            Patient__c = patient.Id,
            Invoice__c = invoice.Id,
            Amount__c = 1500.00,
            Status__c = 'Unpaid'
        );
        insert payment;
    }
    
    @isTest
    static void testGetPatientBillingDetails() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        
        Test.startTest();
        Map<String, Object> details = HMS_PaymentController.getPatientBillingDetails(patient.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, details, 'Billing details should not be null');
        System.assertEquals('John Doe', details.get('patientName'));
        System.assertEquals('john.doe@example.com', details.get('patientEmail'));
        System.assertEquals(138000.00, details.get('totalOutstanding'));
        System.assertEquals(true, details.get('hasOutstanding'));
        System.assertNotEquals(null, details.get('invoiceId'));
        System.assertEquals(138000.00, details.get('paymentAmount'));
        System.assertEquals(1500.00, details.get('sourcePaymentAmountUsd'));
        System.assertEquals(92, details.get('exchangeRate'));
        System.assertNotEquals(null, details.get('invoiceName'));
    }

    @isTest
    static void testCreateRazorpayOrderUsesInvoiceAmount() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Invoice__c invoice = [SELECT Id FROM Invoice__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new RazorpayMock(200, 'captured'));

        Test.startTest();
        Map<String, Object> order = HMS_PaymentController.createRazorpayOrder(patient.Id, invoice.Id);
        Test.stopTest();

        System.assertEquals('order_test_12345', order.get('orderId'));
        System.assertEquals(13800000L, order.get('amountPaise'));
        System.assertEquals(138000.00, order.get('amount'));
        System.assertEquals(1500.00, order.get('sourceAmountUsd'));
        System.assertEquals(92, order.get('exchangeRate'));
    }

    @isTest
    static void testInvoiceAndPaymentRecordContexts() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Invoice__c invoice = [SELECT Id FROM Invoice__c LIMIT 1];
        Payment__c payment = [SELECT Id FROM Payment__c WHERE Invoice__c = :invoice.Id LIMIT 1];

        Test.startTest();
        Map<String, Object> invoiceDetails = HMS_PaymentController.getPatientBillingDetails(invoice.Id);
        Map<String, Object> paymentDetails = HMS_PaymentController.getPatientBillingDetails(payment.Id);
        Test.stopTest();

        System.assertEquals(patient.Id, invoiceDetails.get('patientId'));
        System.assertEquals(invoice.Id, invoiceDetails.get('invoiceId'));
        System.assertEquals(138000.00, invoiceDetails.get('paymentAmount'));
        System.assertEquals(patient.Id, paymentDetails.get('patientId'));
        System.assertEquals(invoice.Id, paymentDetails.get('invoiceId'));
        System.assertEquals(138000.00, paymentDetails.get('paymentAmount'));
    }
    
    @isTest
    static void testGetRazorpayKeyId() {
        Test.startTest();
        String keyId = HMS_PaymentController.getRazorpayKeyId();
        Test.stopTest();
        
        System.assertNotEquals(null, keyId, 'Key ID should be returned');
    }
    
    @isTest
    static void testRecordSuccessfulPaymentWithVerification() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Invoice__c invoice = [SELECT Id FROM Invoice__c LIMIT 1];
        
        // Set up the mock verification callout (successful capture)
        Test.setMock(HttpCalloutMock.class, new RazorpayMock(200, 'captured'));
        String orderId = 'order_test_12345';
        String paymentId = 'pay_test_12345';
        String signature = paymentSignature(orderId, paymentId);
        
        Test.startTest();
        String paymentRecordId = HMS_PaymentController.recordSuccessfulPayment(
            patient.Id,
            invoice.Id,
            paymentId,
            orderId,
            signature,
            'Card'
        );
        Test.stopTest();
        
        System.assertNotEquals(null, paymentRecordId, 'Payment ID should be returned');
        
        // Verify payment record was updated
        Payment__c pmt = [
            SELECT Id, Amount__c, Invoice_Amount_USD__c, Exchange_Rate__c, Paid_Amount_INR__c,
                   Status__c, Payment_Date__c, Payment_Mode__c, Transaction_Reference__c
            FROM Payment__c 
            WHERE Id = :paymentRecordId
        ];
        System.assertEquals(1500.00, pmt.Amount__c);
        System.assertEquals(1500.00, pmt.Invoice_Amount_USD__c);
        System.assertEquals(92, pmt.Exchange_Rate__c);
        System.assertEquals(138000.00, pmt.Paid_Amount_INR__c);
        System.assertEquals('Received', pmt.Status__c);
        System.assertEquals(System.today(), pmt.Payment_Date__c);
        System.assertEquals('pay_test_12345', pmt.Transaction_Reference__c);
        System.assertEquals('Card', pmt.Payment_Mode__c);
        
        // Verify Invoice was updated
        Invoice__c inv = [SELECT Id, Payment_Status__c, Status__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals('Paid', inv.Payment_Status__c);
        System.assertEquals('Paid', inv.Status__c);
    }
    
    @isTest
    static void testFailedVerificationDoesNotMarkInvoicePaid() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Invoice__c invoice = [SELECT Id FROM Invoice__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new RazorpayMock(404, 'failed'));
        String orderId = 'order_test_12345';
        String paymentId = 'pay_test_12345';
        
        Test.startTest();
        try {
            HMS_PaymentController.recordSuccessfulPayment(
                patient.Id,
                invoice.Id,
                paymentId,
                orderId,
                paymentSignature(orderId, paymentId),
                'UPI'
            );
            System.assert(false, 'Failed Razorpay verification must not be recorded as paid.');
        } catch (AuraHandledException expected) {
            System.assert(expected.getMessage().contains('Script-thrown exception'));
        }
        Test.stopTest();
        
        invoice = [SELECT Payment_Status__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals('Unpaid', invoice.Payment_Status__c);
    }

    @IsTest
    static void testGetPaymentCheckoutUrlRequiresLinkedPatient() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Invoice__c invoice = [SELECT Id FROM Invoice__c LIMIT 1];
        try {
            HMS_PaymentController.getPaymentCheckoutUrl(patient.Id, invoice.Id);
            System.assert(false, 'Expected authorization failure without portal link.');
        } catch (AuraHandledException expected) {
            System.assert(expected.getMessage().contains('Script-thrown exception'));
        }
    }

    private static String paymentSignature(String orderId, String paymentId) {
        Razorpay_Setting__mdt setting = [
            SELECT Key_Secret__c
            FROM Razorpay_Setting__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        return EncodingUtil.convertToHex(Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(orderId + '|' + paymentId),
            Blob.valueOf(setting.Key_Secret__c)
        ));
    }
}
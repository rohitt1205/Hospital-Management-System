public without sharing class HMS_PaymentController {
    private static final Decimal INR_PER_USD = 92;

    @AuraEnabled
    public static String getPaymentCheckoutUrl(Id patientId, Id invoiceId) {
        if (patientId == null || invoiceId == null) {
            throw new AuraHandledException('Patient and invoice are required to start payment.');
        }

        Patient__c linkedPatient = PatientPortalLinkService.resolveForRunningUser();
        if (linkedPatient == null || linkedPatient.Id != patientId) {
            throw new AuraHandledException('You are not authorized to pay this invoice.');
        }

        String queryString =
            '?patientId=' + EncodingUtil.urlEncode(String.valueOf(patientId), 'UTF-8') +
            '&invoiceId=' + EncodingUtil.urlEncode(String.valueOf(invoiceId), 'UTF-8');
        String pagePath = Page.PatientRazorpayCheckout.getUrl() + queryString;

        // Stay on the Experience Cloud domain so the member session is reused.
        // salesforce-sites.com is a different domain and sends users to login.
        if (!Test.isRunningTest() && String.isNotBlank(Site.getSiteId())) {
            return Site.getBaseUrl().removeEnd('/') + pagePath;
        }

        for (Domain siteDomain : [
            SELECT Domain
            FROM Domain
            WHERE DomainType = 'DNS' AND Domain LIKE '%.my.site.com'
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            return 'https://' + siteDomain.Domain + pagePath;
        }

        return URL.getOrgDomainUrl().toExternalForm().removeEnd('/') + pagePath;
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPatientBillingDetails(Id patientId) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (patientId == null) {
                throw new AuraHandledException('A Patient, Invoice, or Payment record is required.');
            }

            Id resolvedPatientId;
            Id selectedInvoiceId;
            Schema.SObjectType contextType = patientId.getSObjectType();
            if (contextType == Patient__c.SObjectType) {
                resolvedPatientId = patientId;
            } else if (contextType == Invoice__c.SObjectType) {
                Invoice__c contextInvoice = [
                    SELECT Id, Patient__c
                    FROM Invoice__c
                    WHERE Id = :patientId
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                resolvedPatientId = contextInvoice.Patient__c;
                selectedInvoiceId = contextInvoice.Id;
            } else if (contextType == Payment__c.SObjectType) {
                Payment__c contextPayment = [
                    SELECT Id, Patient__c, Invoice__c, Invoice__r.Patient__c
                    FROM Payment__c
                    WHERE Id = :patientId
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                selectedInvoiceId = contextPayment.Invoice__c;
                resolvedPatientId = contextPayment.Patient__c != null
                    ? contextPayment.Patient__c
                    : (contextPayment.Invoice__r == null ? null : contextPayment.Invoice__r.Patient__c);
            } else {
                throw new AuraHandledException('HMS Payment Gateway supports Patient, Invoice, and Payment records only.');
            }
            if (resolvedPatientId == null) {
                throw new AuraHandledException('The selected record is not linked to a patient.');
            }

            // Retrieve Patient details
            Patient__c patient = [
                SELECT Id, Name, Email__c, Phone__c 
                FROM Patient__c 
                WHERE Id = :resolvedPatientId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            
            result.put('patientName', patient.Name);
            result.put('patientEmail', patient.Email__c);
            result.put('patientPhone', patient.Phone__c);
            result.put('patientId', patient.Id);
            
            // Query unpaid / partially paid invoices
            List<Invoice__c> invoices;
            if (selectedInvoiceId != null) {
                invoices = [
                    SELECT Id, Name, Net_Payable__c, Payment_Status__c
                    FROM Invoice__c
                    WHERE Id = :selectedInvoiceId
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
            } else {
                invoices = [
                    SELECT Id, Name, Net_Payable__c, Payment_Status__c
                    FROM Invoice__c
                    WHERE Patient__c = :resolvedPatientId
                    AND Payment_Status__c IN ('Unpaid', 'Partially Paid')
                    WITH SYSTEM_MODE
                    ORDER BY CreatedDate DESC
                ];
            }
            
            Decimal totalOutstanding = 0.0;
            Id relatedInvoiceId = null;
            Decimal paymentAmount = 0;
            String invoiceName = null;
            
            for (Invoice__c inv : invoices) {
                Boolean isPayable = inv.Payment_Status__c == 'Unpaid' || inv.Payment_Status__c == 'Partially Paid';
                if (isPayable && inv.Net_Payable__c != null) {
                    totalOutstanding += inv.Net_Payable__c;
                }
                if (isPayable && relatedInvoiceId == null) {
                    relatedInvoiceId = inv.Id;
                    paymentAmount = inv.Net_Payable__c == null ? 0 : inv.Net_Payable__c;
                    invoiceName = inv.Name;
                }
            }
            
            result.put('totalOutstanding', toInr(totalOutstanding));
            result.put('invoiceId', relatedInvoiceId);
            result.put('invoiceName', invoiceName);
            result.put('paymentAmount', toInr(paymentAmount));
            result.put('sourcePaymentAmountUsd', paymentAmount);
            result.put('exchangeRate', INR_PER_USD);
            result.put('hasOutstanding', paymentAmount > 0 && relatedInvoiceId != null);
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching billing details: ' + e.getMessage());
        }
        return result;
    }
    
    @AuraEnabled(cacheable=true)
    public static String getRazorpayKeyId() {
        try {
            List<Razorpay_Setting__mdt> settings = [
                SELECT Key_Id__c 
                FROM Razorpay_Setting__mdt 
                WHERE DeveloperName = 'Default' 
                LIMIT 1
            ];
            if (!settings.isEmpty() && String.isNotBlank(settings[0].Key_Id__c)) {
                return settings[0].Key_Id__c;
            }
        } catch (Exception e) {
            // Fallback will be handled in frontend
        }
        return 'rzp_test_dummyKeyId';
    }

    @AuraEnabled
    public static Map<String, Object> startRazorpayPaymentLink(Id patientId, Id invoiceId) {
        try {
            validatePaymentPatient(patientId, invoiceId);

            Invoice__c invoice = loadPayableInvoice(patientId, invoiceId);
            Map<String, Object> billing = getPatientBillingDetails(invoiceId);
            Razorpay_Setting__mdt setting = requireRazorpaySetting();

            Decimal amountInr = toInr(invoice.Net_Payable__c);
            Long amountPaise = toPaise(amountInr);
            String callbackUrl = portalCallbackUrl(patientId, invoiceId);

            HttpRequest request = new HttpRequest();
            request.setEndpoint('https://api.razorpay.com/v1/payment_links');
            request.setMethod('POST');
            request.setHeader('Authorization', basicAuthorization(setting));
            request.setHeader('Content-Type', 'application/json');
            request.setBody(JSON.serialize(new Map<String, Object>{
                'amount' => amountPaise,
                'currency' => 'INR',
                'accept_partial' => false,
                'description' => 'Invoice ' + invoice.Name,
                'reference_id' => uniquePaymentLinkReference(invoice.Id),
                'customer' => new Map<String, Object>{
                    'name' => billing.get('patientName'),
                    'email' => billing.get('patientEmail'),
                    'contact' => billing.get('patientPhone')
                },
                'notify' => new Map<String, Object>{ 'sms' => false, 'email' => false },
                'reminder_enable' => false,
                'notes' => new Map<String, String>{
                    'invoice_id' => String.valueOf(invoice.Id),
                    'patient_id' => String.valueOf(patientId)
                },
                'callback_url' => callbackUrl,
                'callback_method' => 'get'
            }));

            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new AuraHandledException('Razorpay payment link creation failed. ' + extractRazorpayError(response));
            }

            Map<String, Object> link = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String paymentUrl = (String) link.get('short_url');
            String paymentLinkId = (String) link.get('id');
            if (String.isBlank(paymentUrl) || String.isBlank(paymentLinkId)) {
                throw new AuraHandledException('Razorpay did not return a payment link URL.');
            }

            return new Map<String, Object>{
                'paymentUrl' => paymentUrl,
                'paymentLinkId' => paymentLinkId,
                'invoiceName' => invoice.Name,
                'amountInr' => amountInr
            };
        } catch (AuraHandledException handled) {
            throw handled;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to start payment: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String confirmRazorpayPaymentLink(
        Id patientId,
        Id invoiceId,
        String paymentLinkId,
        String razorpayPaymentId
    ) {
        try {
            validatePaymentPatient(patientId, invoiceId);

            Invoice__c invoice = [
                SELECT Id, Name, Patient__c, Net_Payable__c, Payment_Status__c
                FROM Invoice__c
                WHERE Id = :invoiceId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (invoice.Patient__c != patientId) {
                throw new AuraHandledException('The invoice does not belong to this patient.');
            }
            if (invoice.Payment_Status__c == 'Paid') {
                return 'already_paid';
            }

            Razorpay_Setting__mdt setting = requireRazorpaySetting();
            if (String.isBlank(paymentLinkId) || String.isBlank(razorpayPaymentId)) {
                throw new AuraHandledException('Payment confirmation details are missing.');
            }

            HttpRequest linkRequest = new HttpRequest();
            linkRequest.setEndpoint(
                'https://api.razorpay.com/v1/payment_links/' + EncodingUtil.urlEncode(paymentLinkId, 'UTF-8')
            );
            linkRequest.setMethod('GET');
            linkRequest.setHeader('Authorization', basicAuthorization(setting));
            HttpResponse linkResponse = new Http().send(linkRequest);
            if (linkResponse.getStatusCode() != 200) {
                throw new AuraHandledException('Razorpay payment link verification failed. ' + extractRazorpayError(linkResponse));
            }

            Map<String, Object> linkPayload = (Map<String, Object>) JSON.deserializeUntyped(linkResponse.getBody());
            String linkStatus = (String) linkPayload.get('status');
            if (linkStatus != 'paid' && linkStatus != 'partially_paid') {
                throw new AuraHandledException('Razorpay payment link is not paid yet. Current status: ' + linkStatus);
            }

            Map<String, Object> linkNotes = (Map<String, Object>) linkPayload.get('notes');
            if (linkNotes != null) {
                String linkedInvoiceId = (String) linkNotes.get('invoice_id');
                String linkedPatientId = (String) linkNotes.get('patient_id');
                if (linkedInvoiceId != null && linkedInvoiceId != String.valueOf(invoiceId)) {
                    throw new AuraHandledException('Payment link does not match this invoice.');
                }
                if (linkedPatientId != null && linkedPatientId != String.valueOf(patientId)) {
                    throw new AuraHandledException('Payment link does not match this patient.');
                }
            }

            HttpRequest paymentRequest = new HttpRequest();
            paymentRequest.setEndpoint(
                'https://api.razorpay.com/v1/payments/' + EncodingUtil.urlEncode(razorpayPaymentId, 'UTF-8')
            );
            paymentRequest.setMethod('GET');
            paymentRequest.setHeader('Authorization', basicAuthorization(setting));
            HttpResponse paymentResponse = new Http().send(paymentRequest);
            if (paymentResponse.getStatusCode() != 200) {
                throw new AuraHandledException('Razorpay payment verification failed. ' + extractRazorpayError(paymentResponse));
            }

            Map<String, Object> razorpayPayment = (Map<String, Object>) JSON.deserializeUntyped(paymentResponse.getBody());
            String paymentStatus = (String) razorpayPayment.get('status');
            Long paidAmountPaise = decimalToLong((Decimal) razorpayPayment.get('amount'));
            Long expectedAmountPaise = toPaise(toInr(invoice.Net_Payable__c));

            if (paymentStatus != 'captured' && paymentStatus != 'authorized') {
                throw new AuraHandledException('Razorpay payment is not successful. Current status: ' + paymentStatus);
            }
            if (paidAmountPaise != expectedAmountPaise) {
                throw new AuraHandledException('Paid amount does not match the invoice payable amount.');
            }

            String verifiedMode = 'Online';
            String razorpayMethod = (String) razorpayPayment.get('method');
            if (razorpayMethod == 'card') {
                verifiedMode = 'Card';
            } else if (razorpayMethod == 'upi' || razorpayMethod == 'vpa') {
                verifiedMode = 'UPI';
            } else if (razorpayMethod == 'netbanking') {
                verifiedMode = 'Net Banking';
            }

            return persistSuccessfulPayment(patientId, invoiceId, invoice, razorpayPaymentId, verifiedMode, toInr(invoice.Net_Payable__c));
        } catch (AuraHandledException handled) {
            throw handled;
        } catch (Exception e) {
            throw new AuraHandledException('Error confirming payment: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> createRazorpayOrder(Id patientId, Id invoiceId) {
        try {
            Invoice__c invoice = [
                SELECT Id, Name, Patient__c, Net_Payable__c, Payment_Status__c
                FROM Invoice__c
                WHERE Id = :invoiceId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (invoice.Patient__c != patientId) {
                throw new AuraHandledException('The invoice does not belong to this patient.');
            }
            if (invoice.Payment_Status__c == 'Paid' || invoice.Net_Payable__c == null || invoice.Net_Payable__c <= 0) {
                throw new AuraHandledException('This invoice has no payable balance.');
            }

            Razorpay_Setting__mdt setting = getRazorpaySetting();
            if (setting == null || String.isBlank(setting.Key_Id__c) || String.isBlank(setting.Key_Secret__c)
                || setting.Key_Id__c == 'rzp_test_dummyKeyId' || setting.Key_Secret__c == 'dummySecret') {
                throw new AuraHandledException('Razorpay credentials are not configured.');
            }

            Decimal amountInr = toInr(invoice.Net_Payable__c);
            Long amountPaise = toPaise(amountInr);
            HttpRequest request = new HttpRequest();
            request.setEndpoint('https://api.razorpay.com/v1/orders');
            request.setMethod('POST');
            request.setHeader('Authorization', basicAuthorization(setting));
            request.setHeader('Content-Type', 'application/json');
            request.setBody(JSON.serialize(new Map<String, Object>{
                'amount' => amountPaise,
                'currency' => 'INR',
                'receipt' => invoice.Name,
                'notes' => new Map<String, String>{
                    'invoice_id' => String.valueOf(invoice.Id),
                    'patient_id' => String.valueOf(patientId),
                    'source_amount_usd' => String.valueOf(invoice.Net_Payable__c),
                    'inr_per_usd' => String.valueOf(INR_PER_USD)
                }
            }));

            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new AuraHandledException('Razorpay order creation failed. ' + extractRazorpayError(response));
            }

            Map<String, Object> order = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String orderId = (String) order.get('id');
            if (String.isBlank(orderId)) {
                throw new AuraHandledException('Razorpay did not return an order ID.');
            }

            return new Map<String, Object>{
                'orderId' => orderId,
                'amountPaise' => amountPaise,
                'amount' => amountInr,
                'sourceAmountUsd' => invoice.Net_Payable__c,
                'exchangeRate' => INR_PER_USD,
                'invoiceId' => invoice.Id,
                'invoiceName' => invoice.Name,
                'currency' => 'INR'
            };
        } catch (AuraHandledException handled) {
            throw handled;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Razorpay order: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String recordSuccessfulPayment(
        Id patientId,
        Id invoiceId,
        String razorpayPaymentId,
        String razorpayOrderId,
        String razorpaySignature,
        String paymentMode
    ) {
        try {
            Invoice__c invoice = [
                SELECT Id, Patient__c, Net_Payable__c, Payment_Status__c
                FROM Invoice__c
                WHERE Id = :invoiceId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (invoice.Patient__c != patientId) {
                throw new AuraHandledException('The invoice does not belong to this patient.');
            }
            if (invoice.Payment_Status__c == 'Paid') {
                throw new AuraHandledException('This invoice is already paid.');
            }

            Razorpay_Setting__mdt setting = getRazorpaySetting();
            if (setting == null || String.isBlank(setting.Key_Id__c) || String.isBlank(setting.Key_Secret__c)) {
                throw new AuraHandledException('Razorpay credentials are not configured.');
            }

            String expectedSignature = EncodingUtil.convertToHex(Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(razorpayOrderId + '|' + razorpayPaymentId),
                Blob.valueOf(setting.Key_Secret__c)
            ));
            if (String.isBlank(razorpaySignature) || !expectedSignature.equalsIgnoreCase(razorpaySignature)) {
                throw new AuraHandledException('Razorpay payment signature verification failed.');
            }

            String verifiedMode = paymentMode;
            HttpRequest request = new HttpRequest();
            request.setEndpoint('https://api.razorpay.com/v1/payments/' + EncodingUtil.urlEncode(razorpayPaymentId, 'UTF-8'));
            request.setMethod('GET');
            request.setHeader('Authorization', basicAuthorization(setting));
            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() != 200) {
                throw new AuraHandledException('Razorpay payment verification failed. ' + extractRazorpayError(response));
            }

            Map<String, Object> razorpayPayment = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String paymentStatus = (String) razorpayPayment.get('status');
            String paymentOrderId = (String) razorpayPayment.get('order_id');
            Long paidAmountPaise = decimalToLong((Decimal) razorpayPayment.get('amount'));
            Decimal paidAmountInr = toInr(invoice.Net_Payable__c);
            Long expectedAmountPaise = toPaise(paidAmountInr);

            if (paymentStatus != 'captured' && paymentStatus != 'authorized') {
                throw new AuraHandledException('Razorpay payment is not successful. Current status: ' + paymentStatus);
            }
            if (paymentOrderId != razorpayOrderId) {
                throw new AuraHandledException('Razorpay order verification failed.');
            }
            if (paidAmountPaise != expectedAmountPaise) {
                throw new AuraHandledException('Paid amount does not match the invoice payable amount.');
            }

            String razorpayMethod = (String) razorpayPayment.get('method');
            if (razorpayMethod == 'card') {
                verifiedMode = 'Card';
            } else if (razorpayMethod == 'upi' || razorpayMethod == 'vpa') {
                verifiedMode = 'UPI';
            } else if (razorpayMethod == 'netbanking') {
                verifiedMode = 'Net Banking';
            }

            return persistSuccessfulPayment(
                patientId,
                invoiceId,
                invoice,
                razorpayPaymentId,
                verifiedMode,
                paidAmountInr
            );
            
        } catch (Exception e) {
            throw new AuraHandledException('Error recording payment: ' + e.getMessage());
        }
    }

    private static void validatePaymentPatient(Id patientId, Id invoiceId) {
        if (patientId == null || invoiceId == null) {
            throw new AuraHandledException('Patient and invoice are required.');
        }
        Patient__c linkedPatient = PatientPortalLinkService.resolveForRunningUser();
        if (linkedPatient == null || linkedPatient.Id != patientId) {
            throw new AuraHandledException('You are not authorized to pay this invoice.');
        }
    }

    private static Invoice__c loadPayableInvoice(Id patientId, Id invoiceId) {
        Invoice__c invoice = [
            SELECT Id, Name, Patient__c, Net_Payable__c, Payment_Status__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (invoice.Patient__c != patientId) {
            throw new AuraHandledException('The invoice does not belong to this patient.');
        }
        if (invoice.Payment_Status__c == 'Paid' || invoice.Net_Payable__c == null || invoice.Net_Payable__c <= 0) {
            throw new AuraHandledException('This invoice has no payable balance.');
        }
        return invoice;
    }

    private static Razorpay_Setting__mdt requireRazorpaySetting() {
        Razorpay_Setting__mdt setting = getRazorpaySetting();
        if (setting == null || String.isBlank(setting.Key_Id__c) || String.isBlank(setting.Key_Secret__c)
            || setting.Key_Id__c == 'rzp_test_dummyKeyId' || setting.Key_Secret__c == 'dummySecret') {
            throw new AuraHandledException('Razorpay credentials are not configured.');
        }
        return setting;
    }

    private static String portalCallbackUrl(Id patientId, Id invoiceId) {
        String baseUrl;
        if (!Test.isRunningTest() && String.isNotBlank(Site.getSiteId())) {
            baseUrl = Site.getBaseUrl().removeEnd('/');
        } else {
            List<Domain> siteDomains = [
                SELECT Domain
                FROM Domain
                WHERE DomainType = 'DNS' AND Domain LIKE '%.my.site.com'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            baseUrl = siteDomains.isEmpty() ? null : 'https://' + siteDomains[0].Domain;
        }
        if (String.isBlank(baseUrl)) {
            baseUrl = URL.getOrgDomainUrl().toExternalForm().removeEnd('/');
        }
        return baseUrl + '/s/?payment=verify'
            + '&patientId=' + EncodingUtil.urlEncode(String.valueOf(patientId), 'UTF-8')
            + '&invoiceId=' + EncodingUtil.urlEncode(String.valueOf(invoiceId), 'UTF-8');
    }

    private static String persistSuccessfulPayment(
        Id patientId,
        Id invoiceId,
        Invoice__c invoice,
        String razorpayPaymentId,
        String verifiedMode,
        Decimal paidAmountInr
    ) {
        List<Payment__c> payments = [
            SELECT Id, Amount__c, Status__c, Payment_Date__c, Payment_Mode__c, Transaction_Reference__c, Invoice__c, Patient__c
            FROM Payment__c
            WHERE Invoice__c = :invoiceId AND Status__c = 'Unpaid'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Payment__c pmt;
        if (!payments.isEmpty()) {
            pmt = payments[0];
        } else {
            pmt = new Payment__c();
            pmt.Invoice__c = invoiceId;
            pmt.Patient__c = patientId;
        }

        pmt.Amount__c = invoice.Net_Payable__c;
        pmt.Invoice_Amount_USD__c = invoice.Net_Payable__c;
        pmt.Exchange_Rate__c = INR_PER_USD;
        pmt.Paid_Amount_INR__c = paidAmountInr;
        pmt.Status__c = 'Received';
        pmt.Payment_Date__c = System.today();
        pmt.Transaction_Reference__c = razorpayPaymentId;
        pmt.Payment_Mode__c = verifiedMode;

        Database.upsert(pmt, AccessLevel.SYSTEM_MODE);

        Invoice__c inv = new Invoice__c(Id = invoiceId);
        inv.Payment_Status__c = 'Paid';
        inv.Status__c = 'Paid';
        Database.update(inv, AccessLevel.SYSTEM_MODE);

        return pmt.Id;
    }

    private static Razorpay_Setting__mdt getRazorpaySetting() {
        List<Razorpay_Setting__mdt> settings = [
            SELECT Key_Id__c, Key_Secret__c
            FROM Razorpay_Setting__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        return settings.isEmpty() ? null : settings[0];
    }

    private static String basicAuthorization(Razorpay_Setting__mdt setting) {
        return 'Basic ' + EncodingUtil.base64Encode(
            Blob.valueOf(setting.Key_Id__c + ':' + setting.Key_Secret__c)
        );
    }

    private static Long toPaise(Decimal amount) {
        return decimalToLong((amount.setScale(2) * 100));
    }

    private static Decimal toInr(Decimal amountUsd) {
        return amountUsd == null ? 0 : (amountUsd * INR_PER_USD).setScale(2);
    }

    private static Long decimalToLong(Decimal value) {
        return Long.valueOf(String.valueOf(value.setScale(0)));
    }

    private static String uniquePaymentLinkReference(Id invoiceId) {
        // Razorpay requires a unique reference_id per payment link (retries reuse the same invoice).
        String stamp = String.valueOf(Datetime.now().getTime());
        return (String.valueOf(invoiceId).left(18) + 'x' + stamp).left(40);
    }

    private static String extractRazorpayError(HttpResponse response) {
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            Map<String, Object> errorPayload = (Map<String, Object>) payload.get('error');
            if (errorPayload != null && errorPayload.get('description') != null) {
                return String.valueOf(errorPayload.get('description'));
            }
        } catch (Exception ignored) {
        }
        return 'HTTP ' + response.getStatusCode();
    }
}
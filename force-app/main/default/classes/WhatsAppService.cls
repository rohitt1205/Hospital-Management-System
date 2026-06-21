public with sharing class WhatsAppService {

    @future(callout=true)
    public static void sendWhatsAppMessage(String toPhone, String messageBody) {
        try {
            sendWhatsAppMessageSync(toPhone, messageBody, null);
        } catch (Exception ex) {
            System.debug('Error in asynchronous WhatsApp callout: ' + ex.getMessage());
        }
    }

    @future(callout=true)
    public static void sendWhatsAppMessage(String toPhone, String messageBody, String mediaUrl) {
        try {
            sendWhatsAppMessageSync(toPhone, messageBody, mediaUrl);
        } catch (Exception ex) {
            System.debug('Error in asynchronous WhatsApp callout: ' + ex.getMessage());
        }
    }

    public static void sendWhatsAppMessageSync(String toPhone, String messageBody) {
        sendWhatsAppMessageSync(toPhone, messageBody, null);
    }

    public static void sendWhatsAppMessageSync(String toPhone, String messageBody, String mediaUrl) {
        if (String.isBlank(toPhone) || (String.isBlank(messageBody) && String.isBlank(mediaUrl))) {
            return;
        }

        // Sanitize and format phone number to E.164
        String cleanPhone = toPhone.replaceAll('[^0-9+]', '');
        if (!cleanPhone.startsWith('+')) {
            if (cleanPhone.startsWith('91') && cleanPhone.length() == 12) {
                cleanPhone = '+' + cleanPhone;
            } else {
                cleanPhone = '+91' + cleanPhone;
            }
        }

        Twilio_Configuration__mdt config =
            [SELECT Account_SID__c,
                    Auth_Token__c,
                    From_Number__c
             FROM Twilio_Configuration__mdt
             LIMIT 1];

        String endpoint =
            'https://api.twilio.com/2010-04-01/Accounts/' +
            config.Account_SID__c +
            '/Messages.json';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');

        String authString =
            config.Account_SID__c + ':' +
            config.Auth_Token__c;

        String authorizationHeader =
            'Basic ' +
            EncodingUtil.base64Encode(
                Blob.valueOf(authString)
            );

        req.setHeader('Authorization', authorizationHeader);

        req.setHeader(
            'Content-Type',
            'application/x-www-form-urlencoded'
        );

        String body =
            'To=' +
            EncodingUtil.urlEncode(
                'whatsapp:' + cleanPhone,
                'UTF-8'
            )
            +
            '&From=' +
            EncodingUtil.urlEncode(
                config.From_Number__c,
                'UTF-8'
            );

        if (String.isNotBlank(messageBody)) {
            body += '&Body=' + EncodingUtil.urlEncode(messageBody, 'UTF-8');
        }

        if (String.isNotBlank(mediaUrl)) {
            body += '&MediaUrl=' + EncodingUtil.urlEncode(mediaUrl, 'UTF-8');
        }

        req.setBody(body);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('Status Code: ' + res.getStatusCode());
        System.debug('Response: ' + res.getBody());

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            String errorMessage = res.getStatus();
            try {
                Map<String, Object> errorMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                if (errorMap.containsKey('message')) {
                    errorMessage = (String) errorMap.get('message');
                }
            } catch (Exception e) {
                // Ignore parsing errors and fallback to status code
            }
            throw new CalloutException('Twilio error (' + res.getStatusCode() + '): ' + errorMessage);
        }
    }
}
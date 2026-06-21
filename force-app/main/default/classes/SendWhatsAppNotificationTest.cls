@IsTest
private class SendWhatsAppNotificationTest {

    @IsTest
    static void send_skipsBlankInputs() {
        SendWhatsAppNotification.Request blankPhone = new SendWhatsAppNotification.Request();
        blankPhone.messageBody = 'Hello';

        SendWhatsAppNotification.Request blankMessage = new SendWhatsAppNotification.Request();
        blankMessage.phoneNumber = '+15551234567';

        Test.startTest();
        SendWhatsAppNotification.send(
            new List<SendWhatsAppNotification.Request>{ blankPhone, blankMessage }
        );
        Test.stopTest();
    }

    @IsTest
    static void send_enqueuesAsyncCallout() {
        Test.setMock(HttpCalloutMock.class, new WhatsAppCalloutMock());

        SendWhatsAppNotification.Request req = new SendWhatsAppNotification.Request();
        req.phoneNumber = '+15551234567';
        req.messageBody = 'Appointment confirmed';

        Test.startTest();
        SendWhatsAppNotification.send(new List<SendWhatsAppNotification.Request>{ req });
        Test.stopTest();
    }

    @IsTest
    static void whatsAppService_skipsBlankInputs() {
        Test.startTest();
        WhatsAppService.sendWhatsAppMessage(null, 'Hello');
        WhatsAppService.sendWhatsAppMessage('+15551234567', '');
        Test.stopTest();
    }

    @IsTest
    static void whatsAppService_sendsAsyncCallout() {
        Test.setMock(HttpCalloutMock.class, new WhatsAppCalloutMock());

        Test.startTest();
        WhatsAppService.sendWhatsAppMessage('+15551234567', 'Appointment confirmed');
        Test.stopTest();
    }
}
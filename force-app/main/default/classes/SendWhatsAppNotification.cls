public with sharing class SendWhatsAppNotification {

    public class Request {

        @InvocableVariable(required=false)
        public String phoneNumber;

        @InvocableVariable(required=false)
        public String messageBody;
    }

    @InvocableMethod(label='Send WhatsApp Notification')
    public static void send(List<Request> requests) {
        for(Request req : requests) {
            if (String.isBlank(req.phoneNumber) || String.isBlank(req.messageBody)) {
                System.debug('Skipping WhatsApp notification: phoneNumber or messageBody is empty.');
                continue;
            }

            WhatsAppService.sendWhatsAppMessage(
                req.phoneNumber,
                req.messageBody
            );
        }
    }
}
public without sharing class FinalReportTwilioSendQueueable implements Queueable, Database.AllowsCallouts {
    private String recipientPhone;
    private String messageBody;
    private String mediaUrl;
    
    public FinalReportTwilioSendQueueable(String recipientPhone, String messageBody, String mediaUrl) {
        this.recipientPhone = recipientPhone;
        this.messageBody = messageBody;
        this.mediaUrl = mediaUrl;
    }
    
    public void execute(QueueableContext context) {
        WhatsAppService.sendWhatsAppMessageSync(this.recipientPhone, this.messageBody, this.mediaUrl);
    }
}

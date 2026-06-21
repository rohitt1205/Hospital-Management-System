public without sharing class FinalReportPDFSendQueueable implements Queueable, Database.AllowsCallouts {
    private Id reportId;

    public FinalReportPDFSendQueueable(Id reportId) {
        this.reportId = reportId;
    }

    public void execute(QueueableContext context) {
        SendFinalReportWhatsApp.sendReportAsyncExecutor(this.reportId, true);
    }
}

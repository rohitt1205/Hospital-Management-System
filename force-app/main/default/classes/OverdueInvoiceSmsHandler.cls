/**
 * OverdueInvoiceSmsHandler
 * ─────────────────────────────────────────────────────────────────────────────
 * Invocable Apex called by the "Overdue Invoice Reminder" Scheduled Flow.
 *
 * Responsibility:
 *   Send an SMS reminder for overdue invoices.
 *
 * NOTE: This is a placeholder implementation that logs the SMS message.
 *       Replace the body of sendSms() with your actual SMS gateway integration
 *       (e.g., Twilio, MessageBird, or a Named Credential callout).
 *
 * Called from Flow element: "Send SMS Reminder"
 * Action API Name         : OverdueInvoiceSmsHandler
 * ─────────────────────────────────────────────────────────────────────────────
 */
public with sharing class OverdueInvoiceSmsHandler {

    // ─── Inner class for Flow input ──────────────────────────────────────────
    public class SmsRequest {
        @InvocableVariable(label='Patient Phone Number' required=true)
        public String phoneNumber;

        @InvocableVariable(label='Patient Name' required=true)
        public String patientName;

        @InvocableVariable(label='Invoice Amount' required=true)
        public Decimal invoiceAmount;

        @InvocableVariable(label='Due Date' required=true)
        public Date dueDate;

        @InvocableVariable(label='Invoice Number')
        public String invoiceNumber;
    }

    // ─── Inner class for Flow output ─────────────────────────────────────────
    public class SmsResult {
        @InvocableVariable(label='SMS Sent Successfully')
        public Boolean isSuccess;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    // ─── Invocable method: called by Flow ────────────────────────────────────
    @InvocableMethod(
        label       = 'Send Overdue Invoice SMS'
        description = 'Sends an SMS reminder to the patient for an overdue hospital invoice.'
        category    = 'Billing'
    )
    public static List<SmsResult> sendSmsReminders(List<SmsRequest> requests) {
        List<SmsResult> results = new List<SmsResult>();

        for (SmsRequest req : requests) {
            SmsResult result = new SmsResult();
            try {
                // ── Build the SMS message body ──────────────────────────────
                String message = 'Dear ' + req.patientName + ', '
                    + 'Your hospital invoice'
                    + (String.isNotBlank(req.invoiceNumber) ? ' (' + req.invoiceNumber + ')' : '')
                    + ' of ₹' + String.valueOf(req.invoiceAmount)
                    + ' is overdue. '
                    + 'Please pay before ' + String.valueOf(req.dueDate) + '. '
                    + 'Contact the billing department for queries. '
                    + '— Hospital Management System';

                // ── Placeholder: Log the SMS (replace with actual gateway) ──
                // TODO: Integrate with Twilio / SMS gateway API via Named Credential
                //
                // Example Twilio integration:
                // HttpRequest httpReq = new HttpRequest();
                // httpReq.setEndpoint('callout:Twilio_SMS/Messages.json');
                // httpReq.setMethod('POST');
                // httpReq.setBody('To=' + req.phoneNumber + '&Body=' + EncodingUtil.urlEncode(message, 'UTF-8'));
                // Http http = new Http();
                // HttpResponse httpRes = http.send(httpReq);

                System.debug(LoggingLevel.INFO,
                    'OverdueInvoiceSmsHandler: SMS to ' + req.phoneNumber + ' — ' + message);

                result.isSuccess = true;

            } catch (Exception ex) {
                result.isSuccess    = false;
                result.errorMessage = ex.getMessage();
                System.debug(LoggingLevel.ERROR,
                    'OverdueInvoiceSmsHandler: SMS failed — ' + ex.getMessage());
            }
            results.add(result);
        }

        return results;
    }
}
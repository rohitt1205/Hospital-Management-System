/**
 * HMS_RetryBatch
 * ─────────────────────────────────────────────────────────────────────────────
 * Processes AuditLog_Retry__c records with Status__c = 'Pending' that have
 * not exceeded the maximum retry attempts configured in AuditLog_Config__mdt.
 *
 * On success: sets Status__c = 'Succeeded'
 * On failure: increments Attempt_Count__c;
 *             if attempts >= max, sets Status__c = 'Failed' and sends alert email.
 *
 * Batch size: 50 (callout governor limit is 100 per transaction; 50 leaves headroom).
 * Implements Database.AllowsCallouts to enable HTTP callouts from batch execute().
 * ─────────────────────────────────────────────────────────────────────────────
 */
public without sharing class HMS_RetryBatch
        implements Database.Batchable<SObject>, Database.AllowsCallouts {

    private Integer maxAttempts;
    private String  alertEmail;

    // ─── Constructor ──────────────────────────────────────────────────────────
    public HMS_RetryBatch() {
        AuditLog_Config__mdt cfg = loadConfig();
        this.maxAttempts = cfg.Retry_Max_Attempts__c == null
            ? 3
            : cfg.Retry_Max_Attempts__c.intValue();
        this.alertEmail  = cfg.Alert_Email__c;
    }

    // ─── Start ────────────────────────────────────────────────────────────────
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Payload__c, Attempt_Count__c, Last_Error__c,
                   Status__c, Object_Name__c, Record_Id__c
            FROM   AuditLog_Retry__c
            WHERE  Status__c        = 'Pending'
            AND    Attempt_Count__c < :maxAttempts
            ORDER BY CreatedDate ASC
        ]);
    }

    // ─── Execute ──────────────────────────────────────────────────────────────
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<AuditLog_Retry__c> retries = (List<AuditLog_Retry__c>) scope;
        List<AuditLog_Retry__c> toUpdate = new List<AuditLog_Retry__c>();

        for (AuditLog_Retry__c retry : retries) {
            Boolean success = false;
            String  errorMsg = '';

            try {
                if (String.isBlank(retry.Payload__c)) {
                    errorMsg = 'Payload is empty — cannot retry.';
                } else {
                    success = HMS_DatadogCalloutService.retryPayload(
                        retry.Payload__c,
                        retry.Id
                    );
                    if (!success) {
                        errorMsg = 'Datadog returned non-2xx status on retry attempt '
                            + (retry.Attempt_Count__c == null ? 1 : retry.Attempt_Count__c.intValue() + 1);
                    }
                }
            } catch (Exception ex) {
                errorMsg = abbreviate('Exception during retry: ' + ex.getMessage(), 255);
                System.debug(LoggingLevel.ERROR,
                    'HMS_RetryBatch.execute: Error on retry record ' + retry.Id
                    + ' — ' + ex.getMessage());
            }

            Integer currentAttempts = retry.Attempt_Count__c == null
                ? 1
                : retry.Attempt_Count__c.intValue() + 1;

            if (success) {
                toUpdate.add(new AuditLog_Retry__c(
                    Id            = retry.Id,
                    Status__c     = 'Succeeded',
                    Last_Error__c = null
                ));
            } else {
                Boolean maxReached = currentAttempts >= maxAttempts;
                toUpdate.add(new AuditLog_Retry__c(
                    Id              = retry.Id,
                    Attempt_Count__c = Decimal.valueOf(currentAttempts),
                    Last_Error__c   = abbreviate(errorMsg, 255),
                    Status__c       = maxReached ? 'Failed' : 'Pending'
                ));

                if (maxReached) {
                    sendMaxAttemptAlert(retry, currentAttempts);
                }
            }
        }

        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR,
                    'HMS_RetryBatch.execute: Failed to update AuditLog_Retry__c records — '
                    + ex.getMessage());
            }
        }
    }

    // ─── Finish ───────────────────────────────────────────────────────────────
    public void finish(Database.BatchableContext bc) {
        // Count remaining pending records and log summary
        AggregateResult[] counts = [
            SELECT Status__c, COUNT(Id) cnt
            FROM   AuditLog_Retry__c
            WHERE  Status__c IN ('Pending', 'Failed', 'Succeeded')
            GROUP BY Status__c
        ];
        for (AggregateResult ar : counts) {
            System.debug(LoggingLevel.INFO,
                'HMS_RetryBatch.finish: Status=' + ar.get('Status__c')
                + ' Count=' + ar.get('cnt'));
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static AuditLog_Config__mdt loadConfig() {
        List<AuditLog_Config__mdt> configs = [
            SELECT Retry_Max_Attempts__c, Alert_Email__c, Environment__c
            FROM   AuditLog_Config__mdt
            WHERE  DeveloperName = 'Default'
            LIMIT  1
        ];
        return configs.isEmpty() ? new AuditLog_Config__mdt() : configs[0];
    }

    private void sendMaxAttemptAlert(AuditLog_Retry__c retry, Integer attempts) {
        if (String.isBlank(alertEmail)) {
            return;
        }
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ alertEmail });
            mail.setSubject('[HMS Datadog Alert] Retry Record Permanently Failed — ' + retry.Id);
            mail.setPlainTextBody(
                'HMS Audit Log Retry — Maximum Attempts Reached\n' +
                '=================================================\n' +
                'Retry Record Id : ' + retry.Id + '\n' +
                'Object          : ' + retry.Object_Name__c + '\n' +
                'Salesforce Record: ' + retry.Record_Id__c + '\n' +
                'Attempts Made   : ' + attempts + '\n' +
                'Last Error      : ' + retry.Last_Error__c + '\n' +
                'Timestamp       : ' + System.now().format() + '\n\n' +
                'This record has been marked as FAILED and will no longer be retried.\n' +
                'Please investigate Datadog connectivity or manually resend if required.'
            );
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'HMS_RetryBatch: Failed to send max-attempt alert email — ' + ex.getMessage());
        }
    }

    private static String abbreviate(String input, Integer maxLen) {
        if (String.isBlank(input)) {
            return '';
        }
        return input.length() <= maxLen ? input : input.substring(0, maxLen);
    }
}
/**
 * HMS_DatadogCalloutService
 * ─────────────────────────────────────────────────────────────────────────────
 * Makes HTTP POST to Datadog Log Intake API via the Datadog_Logs Named Credential.
 * Called from HMS_DatadogCalloutQueueable (Platform Event path) and HMS_RetryBatch.
 * Never from synchronous record triggers.
 *
 * Named Credential: callout:Datadog_Logs
 * External Credential injects DD-API-KEY header automatically — NEVER hardcoded.
 *
 * On success (200/202): no-op.
 * On failure: creates AuditLog_Retry__c with Status__c = Pending
 *             and sends alert email to address configured in AuditLog_Config__mdt.
 * ─────────────────────────────────────────────────────────────────────────────
 */
public without sharing class HMS_DatadogCalloutService {

    private static final String NAMED_CREDENTIAL = 'callout:Datadog_Logs';
    private static final Integer TIMEOUT_MS       = 10000;
    private static final String  SERVICE           = 'salesforce-hms';
    private static final String  SOURCE            = 'salesforce';
    private static final String  HOSTNAME          = 'salesforce-org';

    // ─── Config ───────────────────────────────────────────────────────────────
    private static AuditLog_Config__mdt getConfig() {
        List<AuditLog_Config__mdt> configs = [
            SELECT Datadog_Endpoint_Path__c, Alert_Email__c, Environment__c
            FROM   AuditLog_Config__mdt
            WHERE  DeveloperName = 'Default'
            LIMIT  1
        ];
        if (configs.isEmpty()) {
            return new AuditLog_Config__mdt(
                Datadog_Endpoint_Path__c = '/api/v2/logs',
                Alert_Email__c           = '',
                Environment__c           = 'production'
            );
        }
        return configs[0];
    }

    // ─── Main Entry Point ─────────────────────────────────────────────────────
    /**
     * Sends a list of HMS_Audit_Event__e events to Datadog in one HTTP POST.
     * @param events  List of platform events from the trigger
     */
    public static void sendToDatadog(List<HMS_Audit_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        AuditLog_Config__mdt cfg = getConfig();
        String endpoint          = NAMED_CREDENTIAL + cfg.Datadog_Endpoint_Path__c;
        String environment       = String.isBlank(cfg.Environment__c) ? 'production' : cfg.Environment__c;
        String alertEmail        = cfg.Alert_Email__c;

        // Build payload
        String jsonBody;
        try {
            jsonBody = buildPayload(events, environment);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'HMS_DatadogCalloutService: Failed to build payload — ' + ex.getMessage());
            createRetryRecords(events, 'Payload build error: ' + ex.getMessage());
            sendAlertEmail(alertEmail, 'Payload Build Failure',
                'Failed to serialise audit events for Datadog: ' + ex.getMessage(), events.size());
            return;
        }

        // Execute callout
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(TIMEOUT_MS);
            req.setBody(jsonBody);

            Http http = new Http();
            HttpResponse resp = http.send(req);

            Integer statusCode = resp.getStatusCode();
            if (statusCode == 200 || statusCode == 202) {
                System.debug(LoggingLevel.INFO,
                    'HMS_DatadogCalloutService: Successfully sent ' + events.size()
                    + ' events to Datadog. HTTP ' + statusCode
                    + ' | Payload preview: ' + abbreviate(jsonBody, 300));
            } else {
                String errMsg = 'HTTP ' + statusCode + ': ' + abbreviate(resp.getBody(), 200);
                System.debug(LoggingLevel.ERROR,
                    'HMS_DatadogCalloutService: Datadog rejected payload — ' + errMsg);
                createRetryRecords(events, errMsg);
                sendAlertEmail(alertEmail, 'Datadog Rejection (HTTP ' + statusCode + ')',
                    errMsg + '\n\nPayload size: ' + jsonBody.length() + ' bytes.', events.size());
            }

        } catch (System.CalloutException ce) {
            String errMsg = 'CalloutException: ' + ce.getMessage();
            System.debug(LoggingLevel.ERROR,
                'HMS_DatadogCalloutService: Callout failed — ' + errMsg);
            createRetryRecords(events, errMsg);
            sendAlertEmail(alertEmail, 'Datadog Callout Failure',
                errMsg, events.size());

        } catch (Exception ex) {
            String errMsg = 'UnexpectedException: ' + ex.getMessage();
            System.debug(LoggingLevel.ERROR,
                'HMS_DatadogCalloutService: Unexpected error — ' + errMsg
                + ' | Stack: ' + ex.getStackTraceString());
            createRetryRecords(events, errMsg);
            sendAlertEmail(alertEmail, 'Datadog Unexpected Failure',
                errMsg, events.size());
        }
    }

    /**
     * Retry variant: sends a raw JSON payload string (from AuditLog_Retry__c.Payload__c).
     * Returns true on success, false on failure.
     */
    public static Boolean retryPayload(String jsonBody, String retryRecordId) {
        AuditLog_Config__mdt cfg = getConfig();
        String endpoint = NAMED_CREDENTIAL + cfg.Datadog_Endpoint_Path__c;
        String alertEmail = cfg.Alert_Email__c;

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(TIMEOUT_MS);
            req.setBody(jsonBody);

            Http http = new Http();
            HttpResponse resp = http.send(req);

            Integer statusCode = resp.getStatusCode();
            if (statusCode == 200 || statusCode == 202) {
                System.debug(LoggingLevel.INFO,
                    'HMS_DatadogCalloutService.retryPayload: Success for retry record '
                    + retryRecordId + '. HTTP ' + statusCode);
                return true;
            } else {
                System.debug(LoggingLevel.ERROR,
                    'HMS_DatadogCalloutService.retryPayload: Datadog rejected. HTTP '
                    + statusCode + ' for retry record ' + retryRecordId);
                return false;
            }

        } catch (System.CalloutException ce) {
            System.debug(LoggingLevel.ERROR,
                'HMS_DatadogCalloutService.retryPayload: CalloutException for '
                + retryRecordId + ' — ' + ce.getMessage());
            return false;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'HMS_DatadogCalloutService.retryPayload: Unexpected error for '
                + retryRecordId + ' — ' + ex.getMessage());
            return false;
        }
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    /**
     * Constructs the Datadog log array payload from Platform Events.
     */
    private static String buildPayload(List<HMS_Audit_Event__e> events, String environment) {
        List<Map<String, Object>> logs = new List<Map<String, Object>>();

        for (HMS_Audit_Event__e evt : events) {
            String objectName  = evt.Object_Name__c == null ? '' : evt.Object_Name__c;
            String action      = evt.Action__c       == null ? '' : evt.Action__c;
            String recordId    = evt.Record_Id__c    == null ? '' : evt.Record_Id__c;
            String userName    = evt.Changed_By_Name__c == null ? '' : evt.Changed_By_Name__c;
            String recordName  = evt.Record_Name__c  == null ? '' : evt.Record_Name__c;
            String sessionId   = evt.Session_Id__c   == null ? '' : evt.Session_Id__c;
            String department  = evt.Department__c   == null ? '' : evt.Department__c;
            String changedById = evt.Changed_By_Id__c == null ? '' : evt.Changed_By_Id__c;

            Map<String, Object> context = parseContext(evt.Context__c);
            Map<String, Object> userCtx = getNestedMap(context, 'user');
            Map<String, Object> orgCtx = getNestedMap(context, 'org');
            Map<String, Object> sessionCtx = getNestedMap(context, 'session');
            Map<String, Object> recordCtx = getNestedMap(context, 'record');

            String operation = stringValue(context.get('operation'));
            String auditEventId = stringValue(context.get('audit_event_id'));
            String userEmail = stringValue(userCtx.get('email'));
            String profileName = stringValue(userCtx.get('profile'));
            String sourceIp = stringValue(sessionCtx.get('source_ip'));
            String clientUi = stringValue(sessionCtx.get('client_ui'));
            String recordUrl = stringValue(recordCtx.get('url'));
            String orgName = stringValue(orgCtx.get('name'));
            String geoCountry = stringValue(sessionCtx.get('geo_country'));
            String geoCity = stringValue(sessionCtx.get('geo_city'));
            String geoRegion = stringValue(sessionCtx.get('geo_region'));
            Object fieldsChangedCount = context.get('fields_changed_count');

            Map<String, Object> attributes = new Map<String, Object>{
                'audit_event_id'       => auditEventId,
                'operation'            => operation,
                'record_id'            => recordId,
                'object_name'          => objectName,
                'action'               => action,
                'changed_by'           => userName,
                'changed_by_id'        => changedById,
                'changed_by_email'     => userEmail,
                'changed_by_profile'   => profileName,
                'changed_fields'       => evt.Changed_Fields__c,
                'fields_changed_count' => fieldsChangedCount,
                'record_name'          => recordName,
                'record_url'           => recordUrl,
                'session_id'           => sessionId,
                'source_ip'            => sourceIp,
                'client_ui'            => clientUi,
                'geo_country'          => geoCountry,
                'geo_region'           => geoRegion,
                'geo_city'             => geoCity,
                'geo_latitude'         => stringValue(sessionCtx.get('geo_latitude')),
                'geo_longitude'        => stringValue(sessionCtx.get('geo_longitude')),
                'geo_isp'              => stringValue(sessionCtx.get('geo_isp')),
                'department'           => department,
                'org_id'               => stringValue(orgCtx.get('id')),
                'org_name'             => orgName,
                'org_domain'           => stringValue(orgCtx.get('domain')),
                'is_sandbox'           => orgCtx.get('is_sandbox'),
                'record_snapshot'      => recordCtx.get('snapshot'),
                'audit_context'        => context
            };

            String message = action + ': ' + recordName + ' on ' + objectName
                + ' (' + recordId + ') by ' + userName;
            if (String.isNotBlank(userEmail)) {
                message += ' <' + userEmail + '>';
            }
            if (String.isNotBlank(profileName)) {
                message += ' [' + profileName + ']';
            }
            if (String.isNotBlank(operation)) {
                message += ' {' + operation + '}';
            }
            if (String.isNotBlank(clientUi)) {
                message += ' via ' + clientUi;
            }
            if (String.isNotBlank(sourceIp)) {
                message += ' from ' + sourceIp;
            }
            if (String.isNotBlank(geoCity) || String.isNotBlank(geoCountry)) {
                message += ' near ' + (String.isNotBlank(geoCity) ? geoCity + ', ' : '') + geoCountry;
            }

            String tags = 'env:' + environment
                + ',object:' + objectName
                + ',action:' + action
                + ',hms-audit:true'
                + ',source:salesforce-hms';
            if (String.isNotBlank(operation)) {
                tags += ',operation:' + operation;
            }
            if (String.isNotBlank(profileName)) {
                tags += ',profile:' + sanitizeTag(profileName);
            }
            if (String.isNotBlank(geoCountry)) {
                tags += ',geo_country:' + sanitizeTag(geoCountry);
            }

            Map<String, Object> logEntry = new Map<String, Object>{
                'message'    => message,
                'service'    => SERVICE,
                'status'     => 'info',
                'ddsource'   => SOURCE,
                'hostname'   => HOSTNAME,
                'ddtags'     => tags,
                'attributes' => attributes
            };
            logs.add(logEntry);
        }

        return JSON.serialize(logs);
    }

    /**
     * Creates AuditLog_Retry__c records for all failed events (one per event).
     * Bulk-safe: collected in a list and inserted in one DML call.
     */
    @TestVisible
    private static void createRetryRecords(List<HMS_Audit_Event__e> events, String errorMessage) {
        List<AuditLog_Retry__c> retries = new List<AuditLog_Retry__c>();
        String abbreviatedError = abbreviate(errorMessage, 255);
        AuditLog_Config__mdt cfg = getConfig();
        String environment = String.isBlank(cfg.Environment__c) ? 'production' : cfg.Environment__c;

        for (HMS_Audit_Event__e evt : events) {
            // Build a single-event JSON array so retryPayload can resend it directly
            String singlePayload;
            try {
                singlePayload = buildPayload(new List<HMS_Audit_Event__e>{ evt }, environment);
            } catch (Exception ex) {
                singlePayload = '[]';
            }

            retries.add(new AuditLog_Retry__c(
                Payload__c       = singlePayload,
                Attempt_Count__c = 1,
                Last_Error__c    = abbreviatedError,
                Status__c        = 'Pending',
                Object_Name__c   = evt.Object_Name__c,
                Record_Id__c     = evt.Record_Id__c
            ));
        }

        if (!retries.isEmpty()) {
            try {
                insert retries;
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR,
                    'HMS_DatadogCalloutService: Failed to create AuditLog_Retry__c records — '
                    + ex.getMessage());
            }
        }
    }

    /**
     * Sends an alert email to the configured devops address.
     * Silently swallows failures so a secondary failure doesn't mask the primary error.
     */
    @TestVisible
    private static void sendAlertEmail(String toAddress, String subject,
                                       String body, Integer eventCount) {
        if (String.isBlank(toAddress)) {
            System.debug(LoggingLevel.WARN,
                'HMS_DatadogCalloutService: Alert email not sent — Alert_Email__c not configured.');
            return;
        }
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ toAddress });
            mail.setSubject('[HMS Datadog Alert] ' + subject);
            mail.setPlainTextBody(
                'HMS Audit Log Failure Alert\n' +
                '============================\n' +
                'Subject  : ' + subject + '\n' +
                'Events   : ' + eventCount + '\n' +
                'Timestamp: ' + System.now().format() + '\n\n' +
                'Error Details:\n' + body + '\n\n' +
                'Affected events have been saved to AuditLog_Retry__c for scheduled retry.\n' +
                'Retry scheduler: HMS Datadog Retry (runs every 15 minutes).'
            );
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'HMS_DatadogCalloutService: Failed to send alert email — ' + ex.getMessage());
        }
    }

    /** Truncates a string safely to maxLen characters. */
    private static String abbreviate(String input, Integer maxLen) {
        if (String.isBlank(input)) {
            return '';
        }
        return input.length() <= maxLen ? input : input.substring(0, maxLen);
    }

    private static Map<String, Object> parseContext(String contextJson) {
        if (String.isBlank(contextJson)) {
            return new Map<String, Object>();
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(contextJson);
        } catch (Exception ex) {
            return new Map<String, Object>();
        }
    }

    private static Map<String, Object> getNestedMap(Map<String, Object> parent, String key) {
        if (parent == null || !parent.containsKey(key) || parent.get(key) == null) {
            return new Map<String, Object>();
        }
        Object value = parent.get(key);
        return value instanceof Map<String, Object>
            ? (Map<String, Object>) value
            : new Map<String, Object>();
    }

    private static String stringValue(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static String sanitizeTag(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.replace(' ', '_').replace(',', '_');
    }
}
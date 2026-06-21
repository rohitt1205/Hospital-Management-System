/**
 * HMS_AuditLogService
 * ─────────────────────────────────────────────────────────────────────────────
 * Single entry point for all HMS audit event logging.
 * Publishes HMS_Audit_Event__e Platform Events which are then consumed
 * asynchronously by HMS_AuditEventTrigger → HMS_DatadogCalloutQueueable → HMS_DatadogCalloutService.
 *
 * IMPORTANT: This class never makes callouts. All callouts happen inside the
 * Platform Event trigger (after insert), keeping record triggers callout-free.
 *
 * Kill switch: checked first via AuditLog_Config__mdt.Is_Logging_Enabled__c.
 * Bulk-safe: accepts List<SObject> overloads for insert/update/delete contexts.
 * Never throws an uncaught exception — all errors are caught and System.debug-logged.
 * ─────────────────────────────────────────────────────────────────────────────
 */
public without sharing class HMS_AuditLogService {

    private static AuditLog_Config__mdt config {
        get {
            if (config == null) {
                List<AuditLog_Config__mdt> configs = [
                    SELECT Is_Logging_Enabled__c, Environment__c
                    FROM   AuditLog_Config__mdt
                    WHERE  DeveloperName = 'Default'
                    LIMIT  1
                ];
                config = configs.isEmpty() ? new AuditLog_Config__mdt(Is_Logging_Enabled__c = true) : configs[0];
            }
            return config;
        }
        set;
    }

    private static Map<String, Object> actorContext {
        get {
            if (actorContext == null) {
                actorContext = loadActorContext();
            }
            return actorContext;
        }
        set;
    }

    private static Map<String, Object> orgContext {
        get {
            if (orgContext == null) {
                orgContext = loadOrgContext();
            }
            return orgContext;
        }
        set;
    }

    public static void log(String objectName, String action, SObject newRecord, SObject oldRecord) {
        log(objectName, action,
            newRecord == null ? new List<SObject>()   : new List<SObject>{ newRecord },
            oldRecord == null ? new List<SObject>()   : new List<SObject>{ oldRecord });
    }

    public static void log(String objectName, String action,
                           List<SObject> newRecords, List<SObject> oldRecords) {
        try {
            if (!config.Is_Logging_Enabled__c) {
                System.debug(LoggingLevel.INFO,
                    'HMS_AuditLogService: Logging disabled via AuditLog_Config__mdt. Skipping.');
                return;
            }

            if ((newRecords == null || newRecords.isEmpty()) &&
                (oldRecords == null || oldRecords.isEmpty())) {
                return;
            }

            String userId    = UserInfo.getUserId();
            String userName  = UserInfo.getUserName();
            String sessionId = resolveSessionId();
            DateTime now     = DateTime.now();
            String environment = String.isBlank(config.Environment__c) ? 'production' : config.Environment__c;

            List<HMS_Audit_Event__e> events = new List<HMS_Audit_Event__e>();
            Integer maxIndex = Math.max(
                newRecords == null ? 0 : newRecords.size(),
                oldRecords == null ? 0 : oldRecords.size()
            );

            for (Integer i = 0; i < maxIndex; i++) {
                SObject newRec = (newRecords != null && i < newRecords.size()) ? newRecords[i] : null;
                SObject oldRec = (oldRecords != null && i < oldRecords.size()) ? oldRecords[i] : null;

                String recordId   = '';
                String recordName = '';

                if (newRec != null) {
                    recordId   = newRec.Id == null ? '' : (String) newRec.Id;
                    recordName = getFieldSafe(newRec, 'Name');
                } else if (oldRec != null) {
                    recordId   = oldRec.Id == null ? '' : (String) oldRec.Id;
                    recordName = getFieldSafe(oldRec, 'Name');
                }

                String changedFieldsJson = maskChangedFields(buildChangedFieldsJson(newRec, oldRec));
                String department        = extractDepartment(newRec, oldRec);
                String operation         = resolveOperation(newRec, oldRec);
                String contextJson       = buildContextJson(
                    objectName, action, operation, recordId, recordName,
                    changedFieldsJson, newRec, oldRec, environment, now
                );

                events.add(new HMS_Audit_Event__e(
                    Record_Id__c       = abbreviate(recordId, 18),
                    Object_Name__c     = abbreviate(objectName, 80),
                    Action__c          = abbreviate(action, 50),
                    Changed_By_Id__c   = abbreviate(userId, 18),
                    Changed_By_Name__c = abbreviate(userName, 80),
                    Changed_Fields__c  = abbreviate(changedFieldsJson, 131072),
                    Record_Name__c     = abbreviate(recordName, 80),
                    Timestamp__c       = now,
                    Session_Id__c      = abbreviate(sessionId, 80),
                    Department__c      = abbreviate(department, 80),
                    Context__c         = abbreviate(contextJson, 131072)
                ));
            }

            if (events.isEmpty()) {
                return;
            }

            List<Database.SaveResult> results = EventBus.publish(events);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                if (!sr.isSuccess()) {
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'HMS_AuditLogService: Failed to publish HMS_Audit_Event__e for record '
                            + (i < events.size() ? events[i].Record_Id__c : 'unknown')
                            + ' | Error: ' + err.getMessage()
                            + ' | Status: ' + err.getStatusCode());
                    }
                }
            }

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'HMS_AuditLogService.log: Unexpected error — ' + ex.getMessage()
                + ' | Stack: ' + ex.getStackTraceString());
        }
    }

    private static String buildContextJson(String objectName, String action, String operation,
                                           String recordId, String recordName,
                                           String changedFieldsJson,
                                           SObject newRec, SObject oldRec,
                                           String environment, DateTime eventTime) {
        Map<String, Object> ctx = new Map<String, Object>{
            'audit_event_id'       => buildAuditEventId(recordId, eventTime),
            'operation'            => operation,
            'action'               => action,
            'fields_changed_count' => countChangedFields(changedFieldsJson),
            'environment'          => environment,
            'event_timestamp'      => eventTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'user'                 => actorContext,
            'org'                  => orgContext,
            'session'              => buildSessionContext(),
            'record'               => new Map<String, Object>{
                'id'       => recordId,
                'name'     => recordName,
                'object'   => objectName,
                'url'      => buildRecordUrl(recordId),
                'snapshot' => HMS_PiiMaskingService.maskSnapshot(
                    buildRecordSnapshot(newRec != null ? newRec : oldRec, objectName)
                )
            }
        };
        return JSON.serialize(ctx);
    }

    private static Map<String, Object> loadActorContext() {
        Map<String, Object> userCtx = new Map<String, Object>{
            'id'       => UserInfo.getUserId(),
            'username' => UserInfo.getUserName(),
            'email'    => '',
            'profile'  => '',
            'type'     => UserInfo.getUserType(),
            'locale'   => UserInfo.getLocale()
        };
        try {
            User u = [
                SELECT Email, Profile.Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            userCtx.put('email', u.Email == null ? '' : u.Email);
            userCtx.put('profile', u.Profile.Name == null ? '' : u.Profile.Name);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'HMS_AuditLogService: Could not load user context — ' + ex.getMessage());
        }
        return userCtx;
    }

    private static Map<String, Object> loadOrgContext() {
        Map<String, Object> orgCtx = new Map<String, Object>{
            'id'         => UserInfo.getOrganizationId(),
            'name'       => UserInfo.getOrganizationName(),
            'domain'     => '',
            'is_sandbox' => false
        };
        try {
            orgCtx.put('domain', URL.getOrgDomainUrl().toExternalForm());
            orgCtx.put('is_sandbox', [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'HMS_AuditLogService: Could not load org context — ' + ex.getMessage());
        }
        return orgCtx;
    }

    private static Map<String, Object> buildSessionContext() {
        Map<String, Object> sessionCtx = new Map<String, Object>{
            'source_ip'  => '',
            'client_ui'  => resolveClientUi()
        };
        if (Test.isRunningTest()) {
            return sessionCtx;
        }
        try {
            Map<String, String> session = Auth.SessionManagement.getCurrentSession();
            if (session != null && session.containsKey('SourceIp')) {
                sessionCtx.put('source_ip', session.get('SourceIp'));
            }
        } catch (Exception ex) { /* unavailable in async or API contexts */ }
        return sessionCtx;
    }

    private static String resolveClientUi() {
        try {
            String theme = UserInfo.getUiThemeDisplayed();
            if (theme == 'Theme4d' || theme == 'Theme4t') {
                return 'Lightning';
            }
            if (theme == 'Theme3') {
                return 'Classic';
            }
            return theme == null ? 'Unknown' : theme;
        } catch (Exception ex) {
            return 'Unknown';
        }
    }

    private static String resolveSessionId() {
        try {
            return UserInfo.getSessionId();
        } catch (Exception ex) {
            return 'async-context';
        }
    }

    private static String buildRecordUrl(String recordId) {
        if (String.isBlank(recordId) || recordId.length() != 18) {
            return '';
        }
        try {
            return URL.getOrgDomainUrl().toExternalForm() + '/' + recordId;
        } catch (Exception ex) {
            return '';
        }
    }

    private static String buildAuditEventId(String recordId, DateTime eventTime) {
        String suffix = String.isBlank(recordId) ? 'norecord' : recordId.right(6);
        return 'HMS-' + String.valueOf(eventTime.getTime()) + '-' + suffix;
    }

    private static String resolveOperation(SObject newRec, SObject oldRec) {
        if (newRec != null && oldRec == null) {
            return 'INSERT';
        }
        if (newRec == null && oldRec != null) {
            return 'DELETE';
        }
        return 'UPDATE';
    }

    private static Integer countChangedFields(String changedFieldsJson) {
        if (String.isBlank(changedFieldsJson) || changedFieldsJson == '{}') {
            return 0;
        }
        try {
            return ((Map<String, Object>) JSON.deserializeUntyped(changedFieldsJson)).size();
        } catch (Exception ex) {
            return 0;
        }
    }

    private static Map<String, Object> buildRecordSnapshot(SObject record, String objectName) {
        Map<String, Object> snapshot = new Map<String, Object>();
        if (record == null) {
            return snapshot;
        }
        for (String fieldName : getSnapshotFieldNames(objectName)) {
            try {
                Object val = record.get(fieldName);
                if (val != null) {
                    snapshot.put(fieldName, String.valueOf(val));
                }
            } catch (Exception ex) { /* field not on record */ }
        }
        return snapshot;
    }

    private static List<String> getSnapshotFieldNames(String objectName) {
        if (objectName == 'Patient__c') {
            return new List<String>{
                'Status__c', 'Patient_Category__c', 'Phone__c', 'Gender__c',
                'Guardian__c', 'Date_of_Birth__c', 'Email__c'
            };
        }
        if (objectName == 'Admission__c') {
            return new List<String>{
                'Status__c', 'Patient__c', 'Ward__c', 'Department__c', 'Insurance_Verified__c'
            };
        }
        if (objectName == 'Invoice__c') {
            return new List<String>{
                'Status__c', 'Payment_Status__c', 'Patient__c', 'Admission__c',
                'Net_Payable__c', 'Gross_Amount__c', 'Insurance_Verified__c'
            };
        }
        if (objectName == 'Medical_Record__c') {
            return new List<String>{
                'Record_Status__c', 'Patient__c', 'Doctor__c', 'Admission__c', 'Diagnosis_Summary__c'
            };
        }
        return new List<String>{ 'Name' };
    }

    private static String buildChangedFieldsJson(SObject newRec, SObject oldRec) {
        Map<String, Object> diff = new Map<String, Object>();

        if (newRec != null && oldRec == null) {
            for (String field : newRec.getPopulatedFieldsAsMap().keySet()) {
                diff.put(field, new Map<String, Object>{
                    'new' => String.valueOf(newRec.get(field))
                });
            }
        } else if (newRec == null && oldRec != null) {
            for (String field : oldRec.getPopulatedFieldsAsMap().keySet()) {
                diff.put(field, new Map<String, Object>{
                    'deleted' => String.valueOf(oldRec.get(field))
                });
            }
        } else if (newRec != null && oldRec != null) {
            Map<String, Object> newFields = newRec.getPopulatedFieldsAsMap();
            Map<String, Object> oldFields = oldRec.getPopulatedFieldsAsMap();
            Set<String> allFields = new Set<String>();
            allFields.addAll(newFields.keySet());
            allFields.addAll(oldFields.keySet());

            for (String field : allFields) {
                Object newVal = newFields.get(field);
                Object oldVal = oldFields.get(field);
                String newStr = newVal == null ? null : String.valueOf(newVal);
                String oldStr = oldVal == null ? null : String.valueOf(oldVal);
                if (newStr != oldStr) {
                    diff.put(field, new Map<String, Object>{
                        'old' => oldStr,
                        'new' => newStr
                    });
                }
            }
        }

        return diff.isEmpty() ? '{}' : JSON.serialize(diff);
    }

    private static String maskChangedFields(String json) {
        return HMS_PiiMaskingService.maskChangedFieldsJson(json);
    }

    private static String abbreviate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || maxLength <= 0) {
            return value == null ? '' : value;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    public static String abbreviateForEvent(String value, Integer maxLength) {
        return abbreviate(value, maxLength);
    }

    private static String getFieldSafe(SObject record, String fieldName) {
        if (record == null) {
            return '';
        }
        try {
            Object val = record.get(fieldName);
            return val == null ? '' : String.valueOf(val);
        } catch (Exception ex) {
            return '';
        }
    }

    private static String extractDepartment(SObject newRec, SObject oldRec) {
        SObject rec = newRec != null ? newRec : oldRec;
        if (rec == null) {
            return '';
        }
        try {
            Object val = rec.get('Department__c');
            if (val != null) {
                return String.valueOf(val);
            }
        } catch (Exception ex) { /* field not on this object */ }
        try {
            Object val = rec.get('Ward__c');
            if (val != null) {
                return String.valueOf(val);
            }
        } catch (Exception ex) { /* field not on this object */ }
        return '';
    }
}
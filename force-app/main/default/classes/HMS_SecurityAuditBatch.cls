/**
 * Polls LoginHistory for new logins and AuthSession for ended sessions (logout).
 */
public without sharing class HMS_SecurityAuditBatch
        implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {

    private DateTime lastLoginProcessed;
    private Map<String, Map<String, String>> previousSessions;
    private Integer publishedCount = 0;

    public HMS_SecurityAuditBatch() {
        HMS_Audit_Tracking__c state = getTrackingState();
        this.lastLoginProcessed = state.Last_Login_Processed__c == null
            ? DateTime.now().addDays(-1)
            : state.Last_Login_Processed__c;
        this.previousSessions = parseSessionMap(state.Active_Session_Map__c);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (Test.isRunningTest()) {
            return Database.getQueryLocator([
                SELECT Id, UserId, LoginTime, SourceIp, LoginType, LoginUrl,
                       Browser, Platform, Status, Application
                FROM LoginHistory
                WHERE LoginTime > :DateTime.now().addDays(1)
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id, UserId, LoginTime, SourceIp, LoginType, LoginUrl,
                   Browser, Platform, Status, Application
            FROM LoginHistory
            WHERE LoginTime > :lastLoginProcessed
            ORDER BY LoginTime ASC
            LIMIT 10000
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        processLoginScope((List<LoginHistory>) scope);
    }

    @TestVisible
    private void processLoginScope(List<LoginHistory> logins) {
        if (!HMS_SecurityAuditService.isEnabled() || logins == null || logins.isEmpty()) {
            return;
        }

        List<HMS_SecurityAuditService.LoginAuditRecord> records =
            new List<HMS_SecurityAuditService.LoginAuditRecord>();
        for (LoginHistory login : logins) {
            records.add(HMS_SecurityAuditService.fromLoginHistory(login));
        }
        processLoginAuditRecords(records);
    }

    @TestVisible
    private void processLoginAuditRecords(List<HMS_SecurityAuditService.LoginAuditRecord> records) {
        if (!HMS_SecurityAuditService.isEnabled() || records == null || records.isEmpty()) {
            return;
        }

        publishedCount += HMS_SecurityAuditService.publishLoginAuditRecords(records);
        for (HMS_SecurityAuditService.LoginAuditRecord record : records) {
            if (record.loginTime != null && record.loginTime > lastLoginProcessed) {
                lastLoginProcessed = record.loginTime;
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!HMS_SecurityAuditService.isEnabled()) {
            return;
        }

        Map<String, Map<String, String>> currentSessions = loadCurrentSessions();
        if (!previousSessions.isEmpty()) {
            List<Map<String, String>> endedSessions = findEndedSessions(previousSessions, currentSessions);
            publishedCount += HMS_SecurityAuditService.publishLogoutEvents(endedSessions);
        }

        HMS_Audit_Tracking__c state = getTrackingState();
        state.Last_Login_Processed__c = lastLoginProcessed;
        state.Active_Session_Map__c = serializeSessionMap(currentSessions);
        upsert state;
    }

    @TestVisible
    private static Map<String, Map<String, String>> loadCurrentSessions() {
        Map<String, Map<String, String>> sessions = new Map<String, Map<String, String>>();
        for (AuthSession session : [
            SELECT Id, UsersId, LoginType, SessionType, CreatedDate, IsCurrent
            FROM AuthSession
            WHERE IsCurrent = true
            LIMIT 5000
        ]) {
            String key = String.valueOf(session.UsersId) + '|' + session.Id;
            sessions.put(key, new Map<String, String>{
                'userId'     => String.valueOf(session.UsersId),
                'sessionId'  => session.Id,
                'sessionKey' => key,
                'loginType'  => session.LoginType == null ? '' : session.LoginType,
                'platform'   => session.SessionType == null ? '' : session.SessionType,
                'sourceIp'   => '',
                'browser'    => '',
                'application'=> ''
            });
        }
        return sessions;
    }

    @TestVisible
    private static List<Map<String, String>> findEndedSessions(
        Map<String, Map<String, String>> previous,
        Map<String, Map<String, String>> current
    ) {
        List<Map<String, String>> ended = new List<Map<String, String>>();
        for (String key : previous.keySet()) {
            if (!current.containsKey(key)) {
                ended.add(previous.get(key));
            }
        }
        return ended;
    }

    private static HMS_Audit_Tracking__c getTrackingState() {
        List<HMS_Audit_Tracking__c> rows = [
            SELECT Id, Last_Login_Processed__c, Active_Session_Map__c
            FROM HMS_Audit_Tracking__c
            WHERE Name = 'Default'
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return new HMS_Audit_Tracking__c(
                Name = 'Default',
                Last_Login_Processed__c = DateTime.now().addDays(-1),
                Active_Session_Map__c = '{}'
            );
        }
        return rows[0];
    }

    @TestVisible
    private static Map<String, Map<String, String>> parseSessionMap(String jsonPayload) {
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();
        if (String.isBlank(jsonPayload) || jsonPayload == '{}') {
            return result;
        }
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(jsonPayload);
            for (String key : raw.keySet()) {
                Object val = raw.get(key);
                if (val instanceof Map<String, Object>) {
                    Map<String, String> entry = new Map<String, String>();
                    for (String innerKey : ((Map<String, Object>) val).keySet()) {
                        Object innerVal = ((Map<String, Object>) val).get(innerKey);
                        entry.put(innerKey, innerVal == null ? '' : String.valueOf(innerVal));
                    }
                    result.put(key, entry);
                }
            }
        } catch (Exception ex) { /* ignore malformed state */ }
        return result;
    }

    @TestVisible
    private static String serializeSessionMap(Map<String, Map<String, String>> sessions) {
        return sessions == null || sessions.isEmpty() ? '{}' : JSON.serialize(sessions);
    }
}
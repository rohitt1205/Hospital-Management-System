/**
 * Builds and publishes login/logout audit platform events.
 */
public without sharing class HMS_SecurityAuditService {

    public class LoginAuditRecord {
        public Id userId;
        public Id loginHistoryId;
        public DateTime loginTime;
        public String sourceIp;
        public String browser;
        public String platform;
        public String loginType;
        public String application;
        public String loginUrl;
        public String status;
    }

    public static Boolean isEnabled() {
        List<AuditLog_Config__mdt> configs = [
            SELECT Is_Login_Audit_Enabled__c
            FROM AuditLog_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        return configs.isEmpty() || configs[0].Is_Login_Audit_Enabled__c != false;
    }

    public static Integer publishLoginEvents(List<LoginHistory> logins) {
        if (!isEnabled() || logins == null || logins.isEmpty()) {
            return 0;
        }

        List<LoginAuditRecord> records = new List<LoginAuditRecord>();
        for (LoginHistory login : logins) {
            records.add(fromLoginHistory(login));
        }
        return publishLoginAuditRecords(records);
    }

    public static Integer publishLoginAuditRecords(List<LoginAuditRecord> records) {
        if (!isEnabled() || records == null || records.isEmpty()) {
            return 0;
        }

        Set<Id> userIds = new Set<Id>();
        for (LoginAuditRecord record : records) {
            userIds.add(record.userId);
        }

        Map<Id, User> usersById = new Map<Id, User>([
            SELECT Id, Name, Username, Email, Profile.Name
            FROM User
            WHERE Id IN :userIds
        ]);

        List<HMS_Audit_Event__e> events = new List<HMS_Audit_Event__e>();
        DateTime now = DateTime.now();

        for (LoginAuditRecord record : records) {
            User u = usersById.get(record.userId);
            String userName = u == null ? String.valueOf(record.userId) : u.Username;
            String displayName = u == null ? userName : u.Name;
            Boolean success = record.status == 'Success';
            String action = success ? 'USER_LOGIN_SUCCESS' : 'USER_LOGIN_FAILED';

            Map<String, Object> context = buildAuthContext(
                action, record.userId, userName, displayName, u, now,
                record.sourceIp, record.browser, record.platform, record.loginType,
                record.application, record.loginUrl, record.status, record.loginTime, null
            );

            events.add(new HMS_Audit_Event__e(
                Record_Id__c       = String.valueOf(record.userId),
                Object_Name__c     = 'User',
                Action__c          = action,
                Changed_By_Id__c   = String.valueOf(record.userId),
                Changed_By_Name__c = HMS_AuditLogService.abbreviateForEvent(userName, 80),
                Changed_Fields__c  = '{}',
                Record_Name__c     = HMS_AuditLogService.abbreviateForEvent(displayName, 80),
                Timestamp__c       = record.loginTime == null ? now : record.loginTime,
                Session_Id__c      = record.loginHistoryId == null ? '' : String.valueOf(record.loginHistoryId),
                Department__c      = '',
                Context__c         = JSON.serialize(context)
            ));
        }

        if (events.isEmpty()) {
            return 0;
        }

        EventBus.publish(events);
        return events.size();
    }

    public static Integer publishLogoutEvents(List<Map<String, String>> endedSessions) {
        if (!isEnabled() || endedSessions == null || endedSessions.isEmpty()) {
            return 0;
        }

        Set<Id> userIds = new Set<Id>();
        for (Map<String, String> session : endedSessions) {
            if (session.containsKey('userId')) {
                userIds.add((Id) session.get('userId'));
            }
        }

        Map<Id, User> usersById = new Map<Id, User>([
            SELECT Id, Name, Username, Email, Profile.Name
            FROM User
            WHERE Id IN :userIds
        ]);

        List<HMS_Audit_Event__e> events = new List<HMS_Audit_Event__e>();
        DateTime now = DateTime.now();

        for (Map<String, String> session : endedSessions) {
            Id userId = (Id) session.get('userId');
            User u = usersById.get(userId);
            String userName = u == null ? String.valueOf(userId) : u.Username;
            String displayName = u == null ? userName : u.Name;

            Map<String, Object> context = buildAuthContext(
                'USER_LOGOUT', userId, userName, displayName, u, now,
                session.get('sourceIp'), session.get('browser'), session.get('platform'),
                session.get('loginType'), session.get('application'), '', 'Success', now,
                session.get('sessionId')
            );

            events.add(new HMS_Audit_Event__e(
                Record_Id__c       = String.valueOf(userId),
                Object_Name__c     = 'User',
                Action__c          = 'USER_LOGOUT',
                Changed_By_Id__c   = String.valueOf(userId),
                Changed_By_Name__c = HMS_AuditLogService.abbreviateForEvent(userName, 80),
                Changed_Fields__c  = '{}',
                Record_Name__c     = HMS_AuditLogService.abbreviateForEvent(displayName, 80),
                Timestamp__c       = now,
                Session_Id__c      = session.get('sessionKey'),
                Department__c      = '',
                Context__c         = JSON.serialize(context)
            ));
        }

        if (events.isEmpty()) {
            return 0;
        }

        EventBus.publish(events);
        return events.size();
    }

    public static LoginAuditRecord fromLoginHistory(LoginHistory login) {
        LoginAuditRecord record = new LoginAuditRecord();
        record.userId = login.UserId;
        record.loginHistoryId = login.Id;
        record.loginTime = login.LoginTime;
        record.sourceIp = login.SourceIp;
        record.browser = login.Browser;
        record.platform = login.Platform;
        record.loginType = login.LoginType;
        record.application = login.Application;
        record.loginUrl = login.LoginUrl;
        record.status = login.Status;
        return record;
    }

    @TestVisible
    private static Map<String, Object> buildAuthContext(
        String action, Id userId, String userName, String displayName, User u, DateTime eventTime,
        String sourceIp, String browser, String platform, String loginType,
        String application, String loginUrl, String status, DateTime loginTime, String sessionId
    ) {
        Map<String, Object> userCtx = new Map<String, Object>{
            'id'       => String.valueOf(userId),
            'username' => userName,
            'name'     => displayName,
            'email'    => u == null || u.Email == null ? '' : u.Email,
            'profile'  => u == null || u.Profile == null ? '' : u.Profile.Name,
            'type'     => 'Standard'
        };

        Map<String, Object> sessionCtx = new Map<String, Object>{
            'source_ip'  => sourceIp == null ? '' : sourceIp,
            'client_ui'  => browser == null ? '' : browser,
            'platform'   => platform == null ? '' : platform,
            'login_type' => loginType == null ? '' : loginType,
            'application'=> application == null ? '' : application,
            'login_url'  => loginUrl == null ? '' : loginUrl,
            'status'     => status == null ? '' : status,
            'session_id' => sessionId == null ? '' : sessionId
        };

        return new Map<String, Object>{
            'audit_event_id'  => 'HMS-AUTH-' + String.valueOf(eventTime.getTime()) + '-' + String.valueOf(userId).right(6),
            'operation'       => action.contains('LOGOUT') ? 'LOGOUT' : 'LOGIN',
            'action'          => action,
            'environment'     => resolveEnvironment(),
            'event_timestamp' => eventTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'login_time'      => loginTime == null ? '' : loginTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'user'            => userCtx,
            'org'             => loadOrgContext(),
            'session'         => sessionCtx,
            'record'          => new Map<String, Object>{
                'id'     => String.valueOf(userId),
                'name'   => displayName,
                'object' => 'User',
                'url'    => buildUserUrl(userId)
            }
        };
    }

    private static String resolveEnvironment() {
        List<AuditLog_Config__mdt> configs = [
            SELECT Environment__c FROM AuditLog_Config__mdt WHERE DeveloperName = 'Default' LIMIT 1
        ];
        return configs.isEmpty() || String.isBlank(configs[0].Environment__c)
            ? 'production'
            : configs[0].Environment__c;
    }

    private static Map<String, Object> loadOrgContext() {
        Map<String, Object> orgCtx = new Map<String, Object>{
            'id' => UserInfo.getOrganizationId(),
            'name' => UserInfo.getOrganizationName(),
            'domain' => '',
            'is_sandbox' => false
        };
        try {
            orgCtx.put('domain', URL.getOrgDomainUrl().toExternalForm());
            orgCtx.put('is_sandbox', [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox);
        } catch (Exception ex) { /* ignore */ }
        return orgCtx;
    }

    private static String buildUserUrl(Id userId) {
        try {
            return URL.getOrgDomainUrl().toExternalForm() + '/' + userId;
        } catch (Exception ex) {
            return '';
        }
    }
}
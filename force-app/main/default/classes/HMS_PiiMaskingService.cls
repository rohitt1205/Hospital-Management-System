/**
 * Masks PII/PHI in audit payloads before they leave Salesforce.
 */
public without sharing class HMS_PiiMaskingService {

    private static final Set<String> MASK_FIELD_NAMES = new Set<String>{
        'Phone__c', 'Email__c', 'Address__c', 'Aadhaar_Last_4__c',
        'Clinical_Notes__c', 'Diagnosis_Summary__c', 'MobilePhone', 'HomePhone',
        'OtherPhone', 'Fax', 'Session_Id__c'
    };

    public static Boolean isEnabled() {
        AuditLog_Config__mdt cfg = getConfig();
        return cfg.Is_Pii_Masking_Enabled__c != false;
    }

    public static String maskFieldValue(String fieldName, String value) {
        if (String.isBlank(value) || String.isBlank(fieldName)) {
            return value;
        }
        if (!isEnabled()) {
            return value;
        }

        String normalized = fieldName.toLowerCase();
        if (fieldName == 'Phone__c' || normalized.contains('phone')) {
            return maskPhone(value);
        }
        if (fieldName == 'Email__c' || normalized.contains('email')) {
            return maskEmail(value);
        }
        if (fieldName == 'Aadhaar_Last_4__c') {
            return maskAadhaar(value);
        }
        if (fieldName == 'Address__c' || normalized.contains('address')) {
            return maskAddress(value);
        }
        if (fieldName == 'Clinical_Notes__c' || fieldName == 'Diagnosis_Summary__c') {
            return '[REDACTED PHI]';
        }
        if (fieldName == 'Session_Id__c') {
            return maskSessionId(value);
        }
        if (MASK_FIELD_NAMES.contains(fieldName)) {
            return '[REDACTED]';
        }
        return value;
    }

    public static String maskChangedFieldsJson(String changedFieldsJson) {
        if (!isEnabled() || String.isBlank(changedFieldsJson) || changedFieldsJson == '{}') {
            return changedFieldsJson;
        }
        try {
            Map<String, Object> diff = (Map<String, Object>) JSON.deserializeUntyped(changedFieldsJson);
            Map<String, Object> masked = new Map<String, Object>();
            for (String fieldName : diff.keySet()) {
                Object entryObj = diff.get(fieldName);
                if (!(entryObj instanceof Map<String, Object>)) {
                    masked.put(fieldName, entryObj);
                    continue;
                }
                Map<String, Object> entry = (Map<String, Object>) entryObj;
                Map<String, Object> maskedEntry = new Map<String, Object>();
                for (String key : entry.keySet()) {
                    Object raw = entry.get(key);
                    maskedEntry.put(
                        key,
                        raw == null ? null : maskFieldValue(fieldName, String.valueOf(raw))
                    );
                }
                masked.put(fieldName, maskedEntry);
            }
            return JSON.serialize(masked);
        } catch (Exception ex) {
            return changedFieldsJson;
        }
    }

    public static Map<String, Object> maskSnapshot(Map<String, Object> snapshot) {
        if (!isEnabled() || snapshot == null || snapshot.isEmpty()) {
            return snapshot == null ? new Map<String, Object>() : snapshot;
        }
        Map<String, Object> masked = new Map<String, Object>();
        for (String fieldName : snapshot.keySet()) {
            Object raw = snapshot.get(fieldName);
            masked.put(fieldName, raw == null ? null : maskFieldValue(fieldName, String.valueOf(raw)));
        }
        return masked;
    }

    public static String maskEmail(String email) {
        if (String.isBlank(email) || !email.contains('@')) {
            return email;
        }
        List<String> parts = email.split('@');
        if (parts.size() != 2) {
            return '[REDACTED EMAIL]';
        }
        String local = parts[0];
        String domain = parts[1];
        String visible = local.length() <= 1 ? '*' : local.substring(0, 1);
        return visible + '***@' + domain;
    }

    public static String maskPhone(String phone) {
        String digits = phone.replaceAll('[^0-9]', '');
        if (digits.length() <= 4) {
            return '****';
        }
        return '******' + digits.substring(digits.length() - 4);
    }

    public static String maskAddress(String address) {
        if (String.isBlank(address) || address.length() <= 8) {
            return '[REDACTED ADDRESS]';
        }
        return address.substring(0, 4) + '...[REDACTED]';
    }

    public static String maskAadhaar(String value) {
        String digits = value.replaceAll('[^0-9]', '');
        if (digits.length() >= 4) {
            return '****-****-' + digits.substring(digits.length() - 4);
        }
        return '****';
    }

    public static String maskSessionId(String sessionId) {
        if (String.isBlank(sessionId) || sessionId.length() <= 8) {
            return '****';
        }
        return sessionId.substring(0, 4) + '****' + sessionId.substring(sessionId.length() - 4);
    }

    public static Map<String, Object> maskContext(Map<String, Object> context) {
        if (!isEnabled() || context == null || context.isEmpty()) {
            return context == null ? new Map<String, Object>() : context;
        }

        Map<String, Object> masked = new Map<String, Object>(context);
        Map<String, Object> userCtx = getNestedMap(masked, 'user');
        if (!userCtx.isEmpty()) {
            if (userCtx.containsKey('email')) {
                userCtx.put('email', maskEmail(String.valueOf(userCtx.get('email'))));
            }
            masked.put('user', userCtx);
        }

        Map<String, Object> sessionCtx = getNestedMap(masked, 'session');
        if (!sessionCtx.isEmpty() && sessionCtx.containsKey('source_ip')) {
            sessionCtx.put('source_ip', maskIpForDisplay(String.valueOf(sessionCtx.get('source_ip'))));
            masked.put('session', sessionCtx);
        }

        Map<String, Object> recordCtx = getNestedMap(masked, 'record');
        if (!recordCtx.isEmpty()) {
            Object snapshotObj = recordCtx.get('snapshot');
            if (snapshotObj instanceof Map<String, Object>) {
                recordCtx.put('snapshot', maskSnapshot((Map<String, Object>) snapshotObj));
            }
            masked.put('record', recordCtx);
        }
        return masked;
    }

    public static String maskIpForDisplay(String ip) {
        if (String.isBlank(ip) || !ip.contains('.')) {
            return ip;
        }
        List<String> octets = ip.split('\\.');
        if (octets.size() != 4) {
            return ip;
        }
        return octets[0] + '.' + octets[1] + '.xxx.xxx';
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

    private static AuditLog_Config__mdt getConfig() {
        List<AuditLog_Config__mdt> configs = [
            SELECT Is_Pii_Masking_Enabled__c
            FROM AuditLog_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        return configs.isEmpty()
            ? new AuditLog_Config__mdt(Is_Pii_Masking_Enabled__c = true)
            : configs[0];
    }
}
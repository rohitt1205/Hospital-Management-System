/**
 * Enriches audit platform events with geolocation before Datadog callout.
 * Applies final PII masking to context JSON.
 */
public without sharing class HMS_AuditEnrichmentService {

    public static List<HMS_Audit_Event__e> enrich(List<HMS_Audit_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return events;
        }

        List<HMS_Audit_Event__e> enriched = new List<HMS_Audit_Event__e>();
        for (HMS_Audit_Event__e evt : events) {
            enriched.add(enrichEvent(evt));
        }
        return enriched;
    }

    private static HMS_Audit_Event__e enrichEvent(HMS_Audit_Event__e evt) {
        HMS_Audit_Event__e copy = cloneEvent(evt);

        copy.Changed_Fields__c = HMS_PiiMaskingService.maskChangedFieldsJson(copy.Changed_Fields__c);

        Map<String, Object> context = parseContext(copy.Context__c);
        if (context.isEmpty()) {
            return copy;
        }

        Map<String, Object> sessionCtx = getNestedMap(context, 'session');
        String sourceIp = stringValue(sessionCtx.get('source_ip'));
        if (String.isNotBlank(sourceIp)) {
            Map<String, String> geo = HMS_GeolocationService.lookupIp(sourceIp);
            if (String.isNotBlank(geo.get('country'))) {
                sessionCtx.put('geo_country', geo.get('country'));
                sessionCtx.put('geo_region', geo.get('region'));
                sessionCtx.put('geo_city', geo.get('city'));
                sessionCtx.put('geo_latitude', geo.get('latitude'));
                sessionCtx.put('geo_longitude', geo.get('longitude'));
                sessionCtx.put('geo_isp', geo.get('isp'));
            }
            context.put('session', sessionCtx);
        }

        context = HMS_PiiMaskingService.maskContext(context);
        copy.Context__c = JSON.serialize(context);
        return copy;
    }

    private static HMS_Audit_Event__e cloneEvent(HMS_Audit_Event__e evt) {
        return new HMS_Audit_Event__e(
            Record_Id__c       = evt.Record_Id__c,
            Object_Name__c     = evt.Object_Name__c,
            Action__c          = evt.Action__c,
            Changed_By_Id__c   = evt.Changed_By_Id__c,
            Changed_By_Name__c = evt.Changed_By_Name__c,
            Changed_Fields__c  = evt.Changed_Fields__c,
            Record_Name__c     = evt.Record_Name__c,
            Timestamp__c       = evt.Timestamp__c,
            Session_Id__c      = evt.Session_Id__c,
            Department__c      = evt.Department__c,
            Context__c         = evt.Context__c
        );
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
}
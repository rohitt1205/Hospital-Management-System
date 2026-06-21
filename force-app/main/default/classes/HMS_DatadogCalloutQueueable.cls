/**
 * HMS_DatadogCalloutQueueable
 * Platform Event triggers cannot make HTTP callouts directly.
 * Platform Event __e records lose field values when passed into Queueable,
 * so event data is serialized to JSON in the constructor and restored in execute().
 */
public without sharing class HMS_DatadogCalloutQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private final String serializedEvents;

    public HMS_DatadogCalloutQueueable(List<HMS_Audit_Event__e> events) {
        List<Map<String, Object>> payloads = new List<Map<String, Object>>();
        if (events != null) {
            for (HMS_Audit_Event__e evt : events) {
                payloads.add(new Map<String, Object>{
                    'Record_Id__c'       => evt.Record_Id__c,
                    'Object_Name__c'     => evt.Object_Name__c,
                    'Action__c'          => evt.Action__c,
                    'Changed_By_Id__c'   => evt.Changed_By_Id__c,
                    'Changed_By_Name__c' => evt.Changed_By_Name__c,
                    'Changed_Fields__c'  => evt.Changed_Fields__c,
                    'Record_Name__c'     => evt.Record_Name__c,
                    'Timestamp__c'       => evt.Timestamp__c == null ? null : evt.Timestamp__c.getTime(),
                    'Session_Id__c'      => evt.Session_Id__c,
                    'Department__c'      => evt.Department__c,
                    'Context__c'         => evt.Context__c
                });
            }
        }
        this.serializedEvents = JSON.serialize(payloads);
    }

    public void execute(QueueableContext context) {
        HMS_DatadogCalloutService.sendToDatadog(
            HMS_AuditEnrichmentService.enrich(deserializeEvents(serializedEvents))
        );
    }

    @TestVisible
    private static List<HMS_Audit_Event__e> deserializeEvents(String jsonPayload) {
        List<HMS_Audit_Event__e> events = new List<HMS_Audit_Event__e>();
        if (String.isBlank(jsonPayload)) {
            return events;
        }

        for (Object item : (List<Object>) JSON.deserializeUntyped(jsonPayload)) {
            Map<String, Object> m = (Map<String, Object>) item;
            Object tsVal = m.get('Timestamp__c');
            DateTime ts = null;
            if (tsVal != null) {
                Long tsLong = tsVal instanceof Long
                    ? (Long) tsVal
                    : Long.valueOf(String.valueOf(tsVal));
                ts = DateTime.newInstance(tsLong);
            }

            events.add(new HMS_Audit_Event__e(
                Record_Id__c       = (String) m.get('Record_Id__c'),
                Object_Name__c     = (String) m.get('Object_Name__c'),
                Action__c          = (String) m.get('Action__c'),
                Changed_By_Id__c   = (String) m.get('Changed_By_Id__c'),
                Changed_By_Name__c = (String) m.get('Changed_By_Name__c'),
                Changed_Fields__c  = (String) m.get('Changed_Fields__c'),
                Record_Name__c     = (String) m.get('Record_Name__c'),
                Timestamp__c       = ts,
                Session_Id__c      = (String) m.get('Session_Id__c'),
                Department__c      = (String) m.get('Department__c'),
                Context__c         = (String) m.get('Context__c')
            ));
        }
        return events;
    }
}
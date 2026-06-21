Map<String, Schema.SObjectField> fields = Schema.SObjectType.Admission__c.fields.getMap();
System.debug('=== Admission fields count: ' + fields.size());
System.debug('=== Admission fields: ' + String.join(new List<String>(fields.keySet()), ', '));

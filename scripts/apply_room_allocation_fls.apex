List<String> parentNames = new List<String>{'HMS_Admin','HMS_Hospital_Staff'};
List<PermissionSet> parents = [
    SELECT Id, Name, Profile.Name
    FROM PermissionSet
    WHERE Name IN :parentNames OR Profile.Name = 'System Administrator'
];
Set<Id> parentIds = new Set<Id>();
for (PermissionSet ps : parents) parentIds.add(ps.Id);
List<String> fields = new List<String>{
    'Bed_Allocation__c.Room__c',
    'Bed_Allocation__c.Patient__c',
    'Bed_Allocation__c.Bed_Number__c',
    'Bed_Allocation__c.Ward_Manager_Approval__c',
    'Bed_Allocation__c.Daily_Rate__c',
    'Room__c.Available_Beds__c'
};
Map<String, FieldPermissions> existing = new Map<String, FieldPermissions>();
for (FieldPermissions fp : [
    SELECT Id, ParentId, Field, PermissionsRead, PermissionsEdit
    FROM FieldPermissions
    WHERE ParentId IN :parentIds AND Field IN :fields
]) {
    existing.put(String.valueOf(fp.ParentId) + '|' + fp.Field, fp);
}
List<FieldPermissions> inserts = new List<FieldPermissions>();
List<FieldPermissions> updates = new List<FieldPermissions>();
for (Id parentId : parentIds) {
    for (String fieldName : fields) {
        String key = String.valueOf(parentId) + '|' + fieldName;
        Boolean editable = fieldName != 'Room__c.Available_Beds__c';
        if (existing.containsKey(key)) {
            FieldPermissions fp = existing.get(key);
            fp.PermissionsRead = true;
            fp.PermissionsEdit = editable;
            updates.add(fp);
        } else {
            inserts.add(new FieldPermissions(
                ParentId = parentId,
                SObjectType = fieldName.substringBefore('.'),
                Field = fieldName,
                PermissionsRead = true,
                PermissionsEdit = editable
            ));
        }
    }
}
if (!inserts.isEmpty()) insert inserts;
if (!updates.isEmpty()) update updates;
System.debug('Applied FLS inserts=' + inserts.size() + ', updates=' + updates.size());

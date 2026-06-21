List<String> parentNames = new List<String>{'HMS_Admin','HMS_Hospital_Staff'};
List<PermissionSet> parents = [
    SELECT Id, Name, Profile.Name
    FROM PermissionSet
    WHERE Name IN :parentNames OR Profile.Name = 'System Administrator'
];
Set<Id> parentIds = new Set<Id>();
for (PermissionSet ps : parents) parentIds.add(ps.Id);
Map<Id, FieldPermissions> existing = new Map<Id, FieldPermissions>();
for (FieldPermissions fp : [
    SELECT Id, ParentId, PermissionsRead, PermissionsEdit
    FROM FieldPermissions
    WHERE SObjectType = 'Room__c'
    AND Field = 'Room__c.Occupied_Beds__c'
    AND ParentId IN :parentIds
]) {
    existing.put(fp.ParentId, fp);
}
List<FieldPermissions> toInsert = new List<FieldPermissions>();
List<FieldPermissions> toUpdate = new List<FieldPermissions>();
for (Id parentId : parentIds) {
    if (existing.containsKey(parentId)) {
        FieldPermissions fp = existing.get(parentId);
        fp.PermissionsRead = true;
        fp.PermissionsEdit = true;
        toUpdate.add(fp);
    } else {
        toInsert.add(new FieldPermissions(
            ParentId = parentId,
            SObjectType = 'Room__c',
            Field = 'Room__c.Occupied_Beds__c',
            PermissionsRead = true,
            PermissionsEdit = true
        ));
    }
}
if (!toInsert.isEmpty()) insert toInsert;
if (!toUpdate.isEmpty()) update toUpdate;
System.debug('Applied Room__c.Occupied_Beds__c FLS to parent count=' + parentIds.size() + ', inserted=' + toInsert.size() + ', updated=' + toUpdate.size());

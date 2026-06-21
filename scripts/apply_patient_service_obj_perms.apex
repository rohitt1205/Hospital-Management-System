List<String> parentNames = new List<String>{'HMS_Admin','HMS_Hospital_Staff'};
List<PermissionSet> parents = [
    SELECT Id, Name
    FROM PermissionSet
    WHERE Name IN :parentNames
];
Set<Id> parentIds = new Set<Id>();
for (PermissionSet ps : parents) parentIds.add(ps.Id);

Map<Id, ObjectPermissions> existingMap = new Map<Id, ObjectPermissions>();
for (ObjectPermissions op : [
    SELECT Id, ParentId, SObjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords
    FROM ObjectPermissions
    WHERE SObjectType = 'Patient_Service__c'
    AND ParentId IN :parentIds
]) {
    existingMap.put(op.ParentId, op);
}

List<ObjectPermissions> toInsert = new List<ObjectPermissions>();
List<ObjectPermissions> toUpdate = new List<ObjectPermissions>();

for (PermissionSet ps : parents) {
    Boolean isSystemAdmin = false;
    Boolean isAdminSet = (ps.Name == 'HMS_Admin');
    
    if (existingMap.containsKey(ps.Id)) {
        ObjectPermissions op = existingMap.get(ps.Id);
        op.PermissionsRead = true;
        op.PermissionsCreate = true;
        op.PermissionsEdit = true;
        op.PermissionsDelete = true;
        op.PermissionsViewAllRecords = (isSystemAdmin || isAdminSet);
        op.PermissionsModifyAllRecords = (isSystemAdmin || isAdminSet);
        toUpdate.add(op);
    } else {
        toInsert.add(new ObjectPermissions(
            ParentId = ps.Id,
            SObjectType = 'Patient_Service__c',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = (isSystemAdmin || isAdminSet),
            PermissionsModifyAllRecords = (isSystemAdmin || isAdminSet)
        ));
    }
}

if (!toInsert.isEmpty()) insert toInsert;
if (!toUpdate.isEmpty()) update toUpdate;
System.debug('Applied Patient_Service__c Object Permissions successfully.');

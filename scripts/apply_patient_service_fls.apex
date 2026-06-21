List<String> parentNames = new List<String>{'HMS_Admin','HMS_Hospital_Staff'};
List<PermissionSet> parents = [
    SELECT Id, Name, Profile.Name
    FROM PermissionSet
    WHERE Name IN :parentNames OR Profile.Name = 'System Administrator'
];
Set<Id> parentIds = new Set<Id>();
for (PermissionSet ps : parents) parentIds.add(ps.Id);

List<String> fields = new List<String>{
    'Patient__c', 'Doctor__c', 'Clinical_Service__c', 'Appointment__c', 
    'Admission__c', 'Service_Date__c', 'Service_Price__c', 'Total_Price__c'
};

Map<String, FieldPermissions> existingMap = new Map<String, FieldPermissions>();
for (FieldPermissions fp : [
    SELECT Id, ParentId, Field, PermissionsRead, PermissionsEdit
    FROM FieldPermissions
    WHERE SObjectType = 'Patient_Service__c'
    AND ParentId IN :parentIds
]) {
    existingMap.put(fp.ParentId + '-' + fp.Field, fp);
}

List<FieldPermissions> toInsert = new List<FieldPermissions>();
List<FieldPermissions> toUpdate = new List<FieldPermissions>();

for (Id parentId : parentIds) {
    for (String f : fields) {
        String fullField = 'Patient_Service__c.' + f;
        String key = parentId + '-' + fullField;
        Boolean isFormula = (f == 'Service_Price__c' || f == 'Total_Price__c');
        
        if (existingMap.containsKey(key)) {
            FieldPermissions fp = existingMap.get(key);
            fp.PermissionsRead = true;
            fp.PermissionsEdit = !isFormula;
            toUpdate.add(fp);
        } else {
            toInsert.add(new FieldPermissions(
                ParentId = parentId,
                SObjectType = 'Patient_Service__c',
                Field = fullField,
                PermissionsRead = true,
                PermissionsEdit = !isFormula
            ));
        }
    }
}

if (!toInsert.isEmpty()) insert toInsert;
if (!toUpdate.isEmpty()) update toUpdate;
System.debug('Applied Patient_Service__c FLS successfully.');

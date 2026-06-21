/**
 * Links a Patient__c record to newly created Experience Cloud (portal) users.
 *
 * When a patient self-registers (or is created by staff) on the Hospital Patient
 * Portal, this provisioner finds an existing Patient__c that matches the user's
 * email and stamps Portal_User__c on it. If no match exists, a new Patient__c is
 * created and linked, so the portal dashboard works immediately.
 *
 * User is a setup object, so Patient__c DML is deferred to an async (@future)
 * context to avoid MIXED_DML_OPERATION during user creation/self-registration.
 */
public without sharing class PatientPortalProvisioner {

    // External (community/portal) user types that should own a Patient__c profile.
    private static final Set<String> EXTERNAL_USER_TYPES = new Set<String>{
        'CustomerSuccess',
        'PowerCustomerSuccess',
        'CspLitePortal'
    };

    // Permission sets a portal patient needs (must match networkMemberGroups).
    private static final Set<String> PATIENT_PERMISSION_SETS = new Set<String>{
        'HMS_Patient_User',
        'HMS_Agentforce_Appointment_Booking'
    };

    public static void handleNewUsers(List<User> newUsers) {
        Set<Id> externalUserIds = new Set<Id>();
        for (User u : newUsers) {
            if (u.IsActive == true && EXTERNAL_USER_TYPES.contains(u.UserType)) {
                externalUserIds.add(u.Id);
            }
        }

        if (externalUserIds.isEmpty()) {
            return;
        }

        // Avoid stacking async calls; if we are already async, run synchronously.
        // Patient__c (non-setup) and PermissionSetAssignment (setup) DML are kept
        // in separate transactions to avoid MIXED_DML_OPERATION.
        if (System.isFuture() || System.isBatch() || System.isQueueable()) {
            linkPatients(externalUserIds);
            assignPermissionSets(externalUserIds);
        } else {
            linkPatientsAsync(externalUserIds);
            assignPermissionSetsAsync(externalUserIds);
        }
    }

    @future
    public static void assignPermissionSetsAsync(Set<Id> userIds) {
        assignPermissionSets(userIds);
    }

    public static void assignPermissionSets(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }

        Map<String, Id> permSetIdsByName = new Map<String, Id>();
        for (PermissionSet ps : [
            SELECT Id, Name FROM PermissionSet WHERE Name IN :PATIENT_PERMISSION_SETS
        ]) {
            permSetIdsByName.put(ps.Name, ps.Id);
        }
        if (permSetIdsByName.isEmpty()) {
            return;
        }

        // Skip assignments that already exist.
        Set<String> existing = new Set<String>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :userIds AND PermissionSetId IN :permSetIdsByName.values()
        ]) {
            existing.add(psa.AssigneeId + '|' + psa.PermissionSetId);
        }

        List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
        for (Id userId : userIds) {
            for (Id permSetId : permSetIdsByName.values()) {
                if (!existing.contains(userId + '|' + permSetId)) {
                    toInsert.add(new PermissionSetAssignment(
                        AssigneeId = userId,
                        PermissionSetId = permSetId
                    ));
                }
            }
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false); // partial success; ignore licence-mismatch rows
        }
    }

    @future
    public static void linkPatientsAsync(Set<Id> userIds) {
        linkPatients(userIds);
    }

    public static void linkPatients(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }

        List<User> users = [
            SELECT Id, Email, FirstName, LastName
            FROM User
            WHERE Id IN :userIds
        ];
        if (users.isEmpty()) {
            return;
        }

        // Skip users that already have a Patient__c linked.
        Set<Id> alreadyLinked = new Set<Id>();
        for (Patient__c p : [
            SELECT Portal_User__c FROM Patient__c WHERE Portal_User__c IN :userIds
        ]) {
            alreadyLinked.add(p.Portal_User__c);
        }

        Set<String> emails = new Set<String>();
        for (User u : users) {
            if (String.isNotBlank(u.Email)) {
                emails.add(u.Email);
            }
        }

        // Existing, unlinked patients keyed by lowercase email for matching.
        Map<String, Patient__c> patientsByEmail = new Map<String, Patient__c>();
        for (Patient__c p : [
            SELECT Id, Email__c, Portal_User__c
            FROM Patient__c
            WHERE Email__c IN :emails AND Portal_User__c = null
        ]) {
            if (String.isNotBlank(p.Email__c)) {
                patientsByEmail.put(p.Email__c.toLowerCase(), p);
            }
        }

        List<Patient__c> toUpdate = new List<Patient__c>();
        List<Patient__c> toInsert = new List<Patient__c>();

        for (User u : users) {
            if (alreadyLinked.contains(u.Id)) {
                continue;
            }

            String emailKey = String.isNotBlank(u.Email) ? u.Email.toLowerCase() : null;
            Patient__c match = emailKey != null ? patientsByEmail.get(emailKey) : null;

            if (match != null) {
                match.Portal_User__c = u.Id;
                toUpdate.add(match);
                patientsByEmail.remove(emailKey); // prevent two users grabbing the same patient
            } else {
                String fullName = (String.isBlank(u.FirstName) ? '' : u.FirstName + ' ')
                    + (String.isBlank(u.LastName) ? 'Patient' : u.LastName);
                toInsert.add(new Patient__c(
                    Name = fullName.trim(),
                    Email__c = u.Email,
                    Status__c = 'Active',
                    Portal_User__c = u.Id
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }
}
/**
 * Canonical patient ↔ portal-user resolution and link integrity for Experience Cloud.
 *
 * Resolution order (first match wins):
 *   1. Patient__c.Portal_User__c = running user Id
 *   2. Portal_Patient_Registry__mdt row for the running user's Username (survives email edits)
 *   3. Patient__c.Email__c matches running user's email (case-insensitive)
 *
 * Self-heal: stamps Portal_User__c and syncs Email__c from the User record when a match
 * is found via registry or email so the direct link works on the next request.
 *
 * enforceUniquePortalUser: trigger helper — one portal login maps to at most one Patient__c.
 */
public without sharing class PatientPortalLinkService {

    @TestVisible
    private static Boolean skipSelfHeal = false;

    private static Boolean enforcingUnique = false;

    public static Patient__c resolveForRunningUser() {
        Id userId = UserInfo.getUserId();
        return resolve(userId, UserInfo.getUserEmail(), fetchUsername(userId));
    }

    public static Patient__c resolve(Id userId, String userEmail) {
        return resolve(userId, userEmail, fetchUsername(userId));
    }

    public static Patient__c resolve(Id userId, String userEmail, String username) {
        if (userId == null) {
            return null;
        }

        // Registry wins over Portal_User__c so admin preview / demo mappings stay explicit.
        Patient__c fromRegistry = resolveFromRegistry(userId, userEmail, username);
        if (fromRegistry != null) {
            return fromRegistry;
        }

        List<Patient__c> byUser = [
            SELECT Id, Name, Patient_ID__c, Patient_Category__c, Status__c, Email__c,
                   Phone__c, Gender__c, Date_of_Birth__c, Blood_Group__c,
                   Address__c, Patient_Approval_Status__c, Portal_User__c
            FROM Patient__c
            WHERE Portal_User__c = :userId
            LIMIT 1
        ];
        if (!byUser.isEmpty()) {
            return byUser[0];
        }

        if (String.isNotBlank(userEmail)) {
            Patient__c fromEmail = resolveByEmail(userId, userEmail, username);
            if (fromEmail != null) {
                return fromEmail;
            }
        }

        return null;
    }

    /** Prefer registry-named patient when several records share the same email. */
    private static Patient__c resolveByEmail(Id userId, String userEmail, String username) {
        String registryName = fetchRegistryPatientName(userId, username);
        if (String.isNotBlank(registryName)) {
            List<Patient__c> named = [
                SELECT Id, Name, Patient_ID__c, Patient_Category__c, Status__c, Email__c,
                       Phone__c, Gender__c, Date_of_Birth__c, Blood_Group__c,
                       Address__c, Patient_Approval_Status__c, Portal_User__c
                FROM Patient__c
                WHERE Email__c = :userEmail AND Name = :registryName
                LIMIT 1
            ];
            if (!named.isEmpty()) {
                return selfHeal(named[0], userId, userEmail);
            }
        }

        List<Patient__c> byEmail = [
            SELECT Id, Name, Patient_ID__c, Patient_Category__c, Status__c, Email__c,
                   Phone__c, Gender__c, Date_of_Birth__c, Blood_Group__c,
                   Address__c, Patient_Approval_Status__c, Portal_User__c
            FROM Patient__c
            WHERE Email__c = :userEmail
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!byEmail.isEmpty()) {
            return selfHeal(byEmail[0], userId, userEmail);
        }
        return null;
    }

    private static String fetchRegistryPatientName(Id userId, String username) {
        List<Portal_Patient_Registry__mdt> rows = new List<Portal_Patient_Registry__mdt>();
        if (String.isNotBlank(username)) {
            rows = [
                SELECT Patient_Record_Name__c
                FROM Portal_Patient_Registry__mdt
                WHERE Active__c = true
                AND Portal_Username__c = :username
                LIMIT 1
            ];
        }
        if (rows.isEmpty() && userId != null) {
            rows = [
                SELECT Patient_Record_Name__c
                FROM Portal_Patient_Registry__mdt
                WHERE Active__c = true
                AND Portal_User_Id__c = :userId
                LIMIT 1
            ];
        }
        return rows.isEmpty() ? null : rows[0].Patient_Record_Name__c;
    }

    /**
     * When a Patient__c is assigned a Portal_User__c, detach that user from every other patient.
     * Prevents colleagues from accidentally pointing two records at the same login.
     */
    public static void enforceUniquePortalUser(List<Patient__c> incoming, Map<Id, Patient__c> oldMap) {
        if (enforcingUnique) {
            return;
        }
        Map<Id, Id> userToKeeperPatient = new Map<Id, Id>();
        for (Patient__c p : incoming) {
            if (p.Portal_User__c == null) {
                continue;
            }
            Patient__c prior = oldMap != null ? oldMap.get(p.Id) : null;
            if (prior != null && p.Portal_User__c == prior.Portal_User__c) {
                continue;
            }
            userToKeeperPatient.put(p.Portal_User__c, p.Id);
        }
        if (userToKeeperPatient.isEmpty()) {
            return;
        }

        List<Patient__c> toClear = new List<Patient__c>();
        for (Patient__c other : [
            SELECT Id, Portal_User__c
            FROM Patient__c
            WHERE Portal_User__c IN :userToKeeperPatient.keySet()
        ]) {
            Id keeperId = userToKeeperPatient.get(other.Portal_User__c);
            if (keeperId != other.Id) {
                other.Portal_User__c = null;
                toClear.add(other);
            }
        }
        if (!toClear.isEmpty()) {
            enforcingUnique = true;
            try {
                update toClear;
            } finally {
                enforcingUnique = false;
            }
        }
    }

    private static Patient__c resolveFromRegistry(Id userId, String userEmail, String username) {
        List<Portal_Patient_Registry__mdt> rows = new List<Portal_Patient_Registry__mdt>();
        if (String.isNotBlank(username)) {
            rows = [
                SELECT Patient_Record_Name__c, Sync_Email_From_User__c
                FROM Portal_Patient_Registry__mdt
                WHERE Active__c = true
                AND Portal_Username__c = :username
                LIMIT 1
            ];
        }
        if (rows.isEmpty() && userId != null) {
            rows = [
                SELECT Patient_Record_Name__c, Sync_Email_From_User__c
                FROM Portal_Patient_Registry__mdt
                WHERE Active__c = true
                AND Portal_User_Id__c = :userId
                LIMIT 1
            ];
        }
        if (rows.isEmpty()) {
            return null;
        }
        String patientName = rows[0].Patient_Record_Name__c;
        List<Patient__c> matches = [
            SELECT Id, Name, Patient_ID__c, Patient_Category__c, Status__c, Email__c,
                   Phone__c, Gender__c, Date_of_Birth__c, Blood_Group__c,
                   Address__c, Patient_Approval_Status__c, Portal_User__c
            FROM Patient__c
            WHERE Name = :patientName
            LIMIT 1
        ];
        if (matches.isEmpty()) {
            return null;
        }
        Patient__c patient = matches[0];
        if (rows[0].Sync_Email_From_User__c && String.isNotBlank(userEmail)) {
            patient.Email__c = userEmail;
        }
        return selfHeal(patient, userId, userEmail);
    }

    private static Patient__c selfHeal(Patient__c patient, Id userId, String userEmail) {
        if (skipSelfHeal) {
            return patient;
        }
        Boolean dirty = false;
        if (patient.Portal_User__c != userId) {
            patient.Portal_User__c = userId;
            dirty = true;
        }
        if (String.isNotBlank(userEmail) && patient.Email__c != userEmail) {
            patient.Email__c = userEmail;
            dirty = true;
        }
        if (dirty) {
            try {
                update patient;
            } catch (Exception ignored) {
                // Return the match even if self-heal DML is blocked; read still works this request.
            }
        }
        return patient;
    }

    private static String fetchUsername(Id userId) {
        List<User> users = [SELECT Username FROM User WHERE Id = :userId LIMIT 1];
        return users.isEmpty() ? null : users[0].Username;
    }
}
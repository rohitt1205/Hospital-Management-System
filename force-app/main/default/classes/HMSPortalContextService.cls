/**
 * Determines whether the running user is a patient portal user or hospital staff/admin.
 */
public without sharing class HMSPortalContextService {

    public static final String ROLE_PATIENT = 'patient';
    public static final String ROLE_STAFF   = 'staff';
    public static final String ROLE_ADMIN   = 'admin';

    public static String resolveRole() {
        if (isAdminUser()) {
            return ROLE_ADMIN;
        }
        if (isStaffUser()) {
            return ROLE_STAFF;
        }
        return ROLE_PATIENT;
    }

    public static Boolean isStaffUser() {
        return isPortalStaffUser();
    }

    public static Boolean canManageAnyAppointmentRequest() {
        return isPortalStaffUser();
    }

    public static Boolean isAdminUser() {
        if (hasPermissionSet('HMS_Admin') || hasPermissionSet('HMS_Portal_Admin')) {
            return true;
        }
        String profileName = currentProfileName();
        return profileName == 'System Administrator';
    }

    public static void assertStaffAccess() {
        if (!isStaffUser()) {
            throw new AuraHandledException('You do not have permission to perform this action.');
        }
    }

    private static Boolean isPortalStaffUser() {
        return hasPermissionSet('HMS_Portal_Admin')
            || hasPermissionSet('HMS_Hospital_Staff')
            || hasPermissionSet('HMS_Admin')
            || hasPermissionSet('HMS_Admission_Agent_Einstein')
            || currentProfileName() == 'System Administrator';
    }

    private static Boolean hasPermissionSet(String permSetName) {
        if (String.isBlank(permSetName)) {
            return false;
        }
        Integer count = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.Name = :permSetName
        ];
        return count > 0;
    }

    private static String currentProfileName() {
        List<User> users = [
            SELECT Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        return users.isEmpty() ? '' : users[0].Profile.Name;
    }
}
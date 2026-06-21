String suffix = UserInfo.getOrganizationId().toLowerCase();
String demoPassword = 'HmsDemo@12345';

for (User userRecord : [
    SELECT Id, Username
    FROM User
    WHERE Username IN :new Set<String>{
        'hms.staff.' + suffix + '@example.com',
        'hms.patient.' + suffix + '@example.com'
    }
]) {
    System.setPassword(userRecord.Id, demoPassword);
    System.debug('Reset password for ' + userRecord.Username);
}

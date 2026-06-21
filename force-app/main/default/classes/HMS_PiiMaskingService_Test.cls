@isTest
private class HMS_PiiMaskingService_Test {

    @isTest
    static void testMaskPhoneAndEmail() {
        System.assertEquals('******7890', HMS_PiiMaskingService.maskPhone('9876547890'));
        System.assertEquals('r***@gmail.com', HMS_PiiMaskingService.maskEmail('raibhoomikakp@gmail.com'));
    }

    @isTest
    static void testMaskContextAndAadhaar() {
        Map<String, Object> context = new Map<String, Object>{
            'user' => new Map<String, Object>{ 'email' => 'secret@example.com' },
            'session' => new Map<String, Object>{ 'source_ip' => '192.168.1.10' }
        };
        Map<String, Object> masked = HMS_PiiMaskingService.maskContext(context);
        System.assert(String.valueOf(((Map<String, Object>) masked.get('user')).get('email')).contains('***'));
        System.assertEquals('****-****-1234', HMS_PiiMaskingService.maskAadhaar('1234'));
    }
}
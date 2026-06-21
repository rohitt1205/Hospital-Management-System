/**
 * Assigns a random outbound email address to Doctor__c records from the org pool.
 */
public without sharing class DoctorEmailAssignmentService {

    @TestVisible
    private static final List<String> DOCTOR_EMAIL_POOL = new List<String>{
        'prasantnov9@gmail.com',
        'joshiprashant.0911@gmail.com'
    };

    @TestVisible
    private static Integer testRandomIndex;

    public static void assignRandomEmail(Doctor__c doctor) {
        if (doctor == null || String.isNotBlank(doctor.Email__c)) {
            return;
        }
        doctor.Email__c = pickRandomEmail();
    }

    public static String pickRandomEmail() {
        if (Test.isRunningTest() && testRandomIndex != null) {
            return DOCTOR_EMAIL_POOL[Math.mod(testRandomIndex, DOCTOR_EMAIL_POOL.size())];
        }
        Integer randomIndex = Math.mod(Math.abs(Crypto.getRandomInteger()), DOCTOR_EMAIL_POOL.size());
        return DOCTOR_EMAIL_POOL[randomIndex];
    }
}
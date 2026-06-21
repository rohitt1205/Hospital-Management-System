public class BillingUtil {
    public static final String ADMISSION = 'Admission';
    public static final String ROOM = 'Room';
    public static final String BED = 'Bed';
    public static final String CONSULTATION = 'Consultation';
    public static final String LAB = 'Lab';
    public static final String MEDICINE = 'Medicine';

    public static Decimal zeroIfNull(Decimal value) {
        return value == null ? 0 : value;
    }

    public static Integer lengthOfStayDays(Datetime startDateTime, Datetime endDateTime) {
        if (startDateTime == null || endDateTime == null) {
            return 1;
        }

        Long milliseconds = endDateTime.getTime() - startDateTime.getTime();
        if (milliseconds <= 0) {
            return 1;
        }

        Double days = ((Double) milliseconds) / 86400000.0;
        Integer billedDays = (Integer) Math.ceil(days);
        return billedDays < 1 ? 1 : billedDays;
    }

    public static String lineItemKey(Id invoiceId, String chargeType, Id sourceRecordId) {
        return String.valueOf(invoiceId) + '|' + String.valueOf(chargeType) + '|' + String.valueOf(sourceRecordId);
    }
}
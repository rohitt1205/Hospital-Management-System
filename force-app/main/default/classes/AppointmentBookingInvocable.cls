/**
 * Shared helpers for Agentforce appointment booking invocable actions.
 * Salesforce allows one @InvocableMethod per Apex class; each capability has its own action class.
 */
public without sharing class AppointmentBookingInvocable {

    private static final String AGENT_BOT_USERNAME_PREFIX = 'hms_patient_assistant@';

    public static Id resolvePatientId(String portalUserIdText) {
        Id portalUserId = normalizePortalUserId(parseOptionalUserId(portalUserIdText));
        if (portalUserId != null && !isAgentRuntimeUser(portalUserId)) {
            try {
                return AppointmentBookingService.resolvePatientIdForUser(portalUserId);
            } catch (AppointmentBookingException ex) {
                Id fallbackPatientId = AppointmentBookingService.resolvePatientIdForServiceAgentFallback();
                if (fallbackPatientId != null) {
                    return fallbackPatientId;
                }
                throw ex;
            }
        }

        Id runningUserId = UserInfo.getUserId();
        if (!isAgentRuntimeUser(runningUserId)) {
            try {
                return AppointmentBookingService.resolvePatientIdForUser(runningUserId);
            } catch (AppointmentBookingException ignored) {
                // Fall through to demo-patient fallback for preview / service agent runs.
            }
        }

        Id fallbackPatientId = AppointmentBookingService.resolvePatientIdForServiceAgentFallback();
        if (fallbackPatientId != null) {
            return fallbackPatientId;
        }
        throw new AppointmentBookingException(
            'We could not find a patient profile linked to your account. Please contact the hospital reception.'
        );
    }

    private static Id parseOptionalUserId(String portalUserIdText) {
        if (String.isBlank(portalUserIdText)) {
            return null;
        }
        try {
            return Id.valueOf(portalUserIdText.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * Embedded messaging may pass a Contact Id (003) or other identity Id instead of User Id (005).
     * Resolve to the portal User Id when possible.
     */
    private static Id normalizePortalUserId(Id rawId) {
        if (rawId == null) {
            return null;
        }
        Schema.SObjectType sobjectType = rawId.getSObjectType();
        if (sobjectType == User.SObjectType) {
            return rawId;
        }
        if (sobjectType == Contact.SObjectType) {
            List<User> portalUsers = [
                SELECT Id
                FROM User
                WHERE ContactId = :rawId
                  AND IsActive = true
                WITH SYSTEM_MODE
                ORDER BY LastLoginDate DESC NULLS LAST
                LIMIT 1
            ];
            return portalUsers.isEmpty() ? null : portalUsers[0].Id;
        }
        return null;
    }

    private static Boolean isAgentRuntimeUser(Id userId) {
        if (userId == null) {
            return false;
        }
        List<User> users = [
            SELECT Username
            FROM User
            WHERE Id = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (users.isEmpty() || String.isBlank(users[0].Username)) {
            return false;
        }
        return users[0].Username.toLowerCase().startsWith(AGENT_BOT_USERNAME_PREFIX);
    }

    public static Date parseDate(String dateText) {
        if (String.isBlank(dateText)) {
            return null;
        }
        String trimmed = dateText.trim();
        try {
            return Date.valueOf(trimmed);
        } catch (Exception ex) {
            Date parsed = parseFlexibleDate(trimmed);
            if (parsed != null) {
                return parsed;
            }
            throw new AppointmentBookingException(
                'Could not understand the date "' + trimmed + '". Please use YYYY-MM-DD format.'
            );
        }
    }

    private static final Map<String, Integer> MONTH_NAME_TO_NUMBER = new Map<String, Integer>{
        'january' => 1, 'jan' => 1,
        'february' => 2, 'feb' => 2,
        'march' => 3, 'mar' => 3,
        'april' => 4, 'apr' => 4,
        'may' => 5,
        'june' => 6, 'jun' => 6,
        'july' => 7, 'jul' => 7,
        'august' => 8, 'aug' => 8,
        'september' => 9, 'sep' => 9, 'sept' => 9,
        'october' => 10, 'oct' => 10,
        'november' => 11, 'nov' => 11,
        'december' => 12, 'dec' => 12
    };

    private static Date parseFlexibleDate(String dateText) {
        if (String.isBlank(dateText)) {
            return null;
        }
        String normalized = dateText.trim().toLowerCase();
        normalized = normalized.replaceAll('(\\d+)(st|nd|rd|th)\\b', '$1');
        normalized = normalized.replace(',', ' ').replaceAll('\\s+', ' ').trim();

        Date delimited = parseDelimitedDate(normalized);
        if (delimited != null) {
            return delimited;
        }

        List<String> tokens = normalized.split(' ');
        if (tokens.size() < 3) {
            return null;
        }

        Integer year;
        Integer month;
        Integer day;
        try {
            year = Integer.valueOf(tokens[tokens.size() - 1]);
            if (year < 100) {
                year += 2000;
            }
        } catch (Exception ex) {
            return null;
        }

        String first = tokens[0];
        String second = tokens[1];
        if (MONTH_NAME_TO_NUMBER.containsKey(first)) {
            month = MONTH_NAME_TO_NUMBER.get(first);
            day = Integer.valueOf(second);
        } else if (MONTH_NAME_TO_NUMBER.containsKey(second)) {
            day = Integer.valueOf(first);
            month = MONTH_NAME_TO_NUMBER.get(second);
        } else {
            return null;
        }

        return buildSafeDate(year, month, day);
    }

    private static Date parseDelimitedDate(String dateText) {
        if (!dateText.contains('/') && !dateText.contains('-')) {
            return null;
        }
        List<String> parts = dateText.split('[\\-/]');
        if (parts.size() != 3) {
            return null;
        }
        try {
            Integer p0 = Integer.valueOf(parts[0]);
            Integer p1 = Integer.valueOf(parts[1]);
            Integer year = Integer.valueOf(parts[2]);
            if (year < 100) {
                year += 2000;
            }
            Integer day;
            Integer month;
            if (p0 > 12) {
                day = p0;
                month = p1;
            } else if (p1 > 12) {
                month = p0;
                day = p1;
            } else {
                day = p0;
                month = p1;
            }
            return buildSafeDate(year, month, day);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date buildSafeDate(Integer year, Integer month, Integer day) {
        if (year == null || month == null || day == null || month < 1 || month > 12 || day < 1 || day > 31) {
            return null;
        }
        try {
            return Date.newInstance(year, month, day);
        } catch (Exception ex) {
            return null;
        }
    }

    public static Id parseId(String idText, String fieldLabel) {
        if (String.isBlank(idText)) {
            return null;
        }
        try {
            return Id.valueOf(idText.trim());
        } catch (Exception ex) {
            throw new AppointmentBookingException('Invalid ' + fieldLabel + ' value provided.');
        }
    }

    public static Id parseOptionalId(String idText, String fieldLabel) {
        if (String.isBlank(idText) || AppointmentBookingService.isAnyDoctorPreference(idText)) {
            return null;
        }
        return parseId(idText, fieldLabel);
    }

    public static String normalizeDoctorNameInput(String doctorName) {
        if (AppointmentBookingService.isAnyDoctorPreference(doctorName)) {
            return null;
        }
        return doctorName;
    }

    /**
     * Agent LLM calls often land compound patient text in a single field
     * (e.g. "cardiology, 3rd August 2026, morning"). Extract structured values.
     */
    public static void normalizeBookingRequest(AppointmentBookingInvocableBook.Request req) {
        if (req == null) {
            return;
        }

        List<String> candidateParts = new List<String>();
        addBookingPart(candidateParts, req.departmentName);
        addBookingPart(candidateParts, req.appointmentDate);
        addBookingPart(candidateParts, req.appointmentTime);
        addBookingPart(candidateParts, req.symptoms);
        if (candidateParts.isEmpty()) {
            return;
        }

        String departmentName = req.departmentName;
        String appointmentDate = req.appointmentDate;
        String appointmentTime = req.appointmentTime;

        for (String part : candidateParts) {
            String trimmed = part.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            if (String.isBlank(departmentName) && looksLikeDepartment(trimmed)) {
                departmentName = capitalizeDepartment(trimmed);
                continue;
            }
            if (String.isBlank(appointmentTime) && AppointmentBookingService.isTimeOfDayPreference(trimmed)) {
                appointmentTime = trimmed;
                continue;
            }
            if (looksLikeClockTime(trimmed)) {
                if (String.isBlank(appointmentTime) || AppointmentBookingService.isTimeOfDayPreference(appointmentTime)) {
                    appointmentTime = trimmed;
                }
                continue;
            }
            Date parsedDate = parseFlexibleDate(trimmed);
            if (parsedDate != null && shouldReplaceDateValue(appointmentDate)) {
                appointmentDate = String.valueOf(parsedDate);
                continue;
            }
            if (String.isBlank(departmentName) && !containsDateToken(trimmed) && !AppointmentBookingService.isTimeOfDayPreference(trimmed)) {
                departmentName = capitalizeDepartment(trimmed);
            }
        }

        req.departmentName = departmentName;
        req.appointmentDate = appointmentDate;
        req.appointmentTime = appointmentTime;
    }

    private static Boolean shouldReplaceDateValue(String currentValue) {
        if (String.isBlank(currentValue)) {
            return true;
        }
        if (currentValue.contains(',')) {
            return true;
        }
        return parseFlexibleDate(currentValue) == null;
    }

    private static void addBookingPart(List<String> parts, String value) {
        if (String.isBlank(value)) {
            return;
        }
        if (value.contains(',')) {
            for (String token : value.split(',')) {
                parts.add(token);
            }
        } else {
            parts.add(value);
        }
    }

    private static Boolean looksLikeClockTime(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String normalized = value.trim().toLowerCase();
        return normalized.contains(':')
            || normalized.endsWith('am')
            || normalized.endsWith('pm');
    }

    private static Boolean containsDateToken(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String normalized = value.trim().toLowerCase();
        if (normalized.contains('-') || normalized.contains('/')) {
            return true;
        }
        for (String month : MONTH_NAME_TO_NUMBER.keySet()) {
            if (normalized.contains(month)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean looksLikeDepartment(String value) {
        if (String.isBlank(value) || containsDateToken(value) || looksLikeClockTime(value)) {
            return false;
        }
        if (AppointmentBookingService.isTimeOfDayPreference(value)) {
            return false;
        }
        String normalized = value.trim().toLowerCase();
        Set<String> knownDepartments = new Set<String>{
            'cardiology', 'general medicine', 'orthopedics', 'neurology', 'oncology',
            'emergency', 'radiology', 'labs', 'pediatrics', 'gynecology'
        };
        for (String department : knownDepartments) {
            if (normalized.contains(department)) {
                return true;
            }
        }
        return normalized.length() <= 40 && !normalized.contains('appointment') && !normalized.contains('book');
    }

    private static String capitalizeDepartment(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        String trimmed = value.trim();
        return trimmed.substring(0, 1).toUpperCase() + trimmed.substring(1);
    }
}
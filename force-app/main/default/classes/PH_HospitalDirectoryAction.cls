// Curated public-directory facade. The action runs in system context and only
// queries the explicitly approved public fields below. Confidential fields are
// absent from both SOQL and response construction.
public without sharing class PH_HospitalDirectoryAction {
    private static final String FALLBACK =
        'Sorry, I couldn\'t find that information. Please contact the hospital helpdesk for further assistance.';

    public class Request {
        @InvocableVariable(required=true label='Request Type' description='Service Request, Department, Doctor, Facility, Admission Fee, Insurance, Subsidy, or Hospital Info')
        public String requestType;

        @InvocableVariable(label='Search Term' description='Optional department name, doctor name, ward type, or room type')
        public String searchTerm;

        @InvocableVariable(label='Information Type' description='For Hospital Info: Timings, Location, Contact, or Ambulance')
        public String informationType;
    }

    public class Response {
        @InvocableVariable(label='Answer' description='Safe patient-facing answer containing no record IDs or confidential fields')
        public String answer;

        @InvocableVariable(label='Information Found')
        public Boolean found;
    }

    @InvocableMethod(
        label='Patient Helpdesk Hospital Directory'
        description='Returns allowlisted public hospital information. Never returns patient data, record IDs, doctor email, or registration number.'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            Response response = new Response();
            try {
                String requestType = normalize(request == null ? null : request.requestType);
                String searchTerm = request == null ? null : clean(request.searchTerm);
                String informationType = request == null ? null : clean(request.informationType);

                if (requestType == 'service request' || requestType == 'servicerequest') {
                    response.answer = serviceRequestOptions(informationType);
                } else if (requestType == 'department') {
                    response.answer = departmentAnswer(searchTerm);
                } else if (requestType == 'doctor') {
                    response.answer = doctorAnswer(searchTerm);
                } else if (requestType == 'facility') {
                    response.answer = facilityAnswer(searchTerm);
                } else if (requestType == 'admission fee' || requestType == 'admissionfee') {
                    response.answer = admissionFeeAnswer();
                } else if (requestType == 'insurance') {
                    response.answer = insuranceAnswer(searchTerm);
                } else if (requestType == 'subsidy' || requestType == 'subsidies') {
                    response.answer = subsidyAnswer();
                } else if (requestType == 'hospital info' || requestType == 'hospitalinfo') {
                    response.answer = hospitalInfoAnswer(informationType);
                } else {
                    response.answer = FALLBACK;
                }
            } catch (Exception ex) {
                response.answer = FALLBACK;
            }
            response.found = response.answer != FALLBACK;
            responses.add(response);
        }
        return responses;
    }

    private static String serviceRequestOptions(String informationType) {
        String requestName = normalize(informationType) == 'admission' ? 'admission' : 'appointment';
        return 'You can request an ' + requestName +
            ' through Reception, Online, Emergency/Direct, or Doctor Referral. ' +
            'Which option would you like to use?';
    }

    private static String departmentAnswer(String searchTerm) {
        List<Department__c> records;
        if (String.isBlank(searchTerm)) {
            records = [
                SELECT Name, Department_Type__c, Active__c
                FROM Department__c
                WITH SYSTEM_MODE
                ORDER BY Name
                LIMIT 100
            ];
        } else {
            String pattern = '%' + searchTerm + '%';
            records = [
                SELECT Name, Department_Type__c, Active__c
                FROM Department__c
                WHERE Name LIKE :pattern
                WITH SYSTEM_MODE
                ORDER BY Name
                LIMIT 25
            ];
        }
        if (records.isEmpty()) {
            return String.isBlank(searchTerm)
                ? 'No active hospital departments are currently listed. Please check again later.'
                : 'No, ' + searchTerm + ' is not currently listed as an available hospital department. Please check again later.';
        }

        List<String> details = new List<String>();
        for (Department__c department : records) {
            String availability = department.Active__c == true ? 'Available' : 'Unavailable';
            String typeName = String.isBlank(department.Department_Type__c)
                ? 'Type not specified'
                : department.Department_Type__c;
            details.add(department.Name + ' - ' + typeName + ' - ' + availability);
        }
        return 'Hospital departments: ' + String.join(details, '; ') + '.';
    }

    private static String doctorAnswer(String searchTerm) {
        List<Doctor__c> records = [
            SELECT Name, Department__r.Name, Specialization__c, Specialization_Type__c,
                   Experience__c, Consultation_Fee__c, Availability_Status__c,
                   Max_Daily_Appointments__c
            FROM Doctor__c
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 500
        ];
        if (!String.isBlank(searchTerm)) {
            String normalizedSearch = normalize(searchTerm);
            List<Doctor__c> matches = new List<Doctor__c>();
            for (Doctor__c doctor : records) {
                String departmentName = doctor.Department__r == null ? null : doctor.Department__r.Name;
                if (matchesSearch(normalizedSearch, doctor.Name) ||
                    matchesSearch(normalizedSearch, departmentName) ||
                    matchesSearch(normalizedSearch, doctor.Specialization__c) ||
                    matchesSearch(normalizedSearch, doctor.Specialization_Type__c)) {
                    matches.add(doctor);
                }
            }
            records = matches;
        }
        if (records.isEmpty()) {
            return String.isBlank(searchTerm)
                ? 'No public doctor records are currently listed. Please check again later.'
                : 'No, no public doctor record matching ' + searchTerm + ' is currently listed. Please check again later.';
        }

        List<String> details = new List<String>();
        for (Doctor__c doctor : records) {
            String departmentName = doctor.Department__r == null
                ? 'Department not specified'
                : doctor.Department__r.Name;
            String specialization = !String.isBlank(doctor.Specialization__c)
                ? doctor.Specialization__c
                : doctor.Specialization_Type__c;
            if (String.isBlank(specialization)) specialization = 'Not specified';
            String experience = doctor.Experience__c == null
                ? 'Experience not specified'
                : String.valueOf(doctor.Experience__c) + ' years experience';
            String fee = doctor.Consultation_Fee__c == null
                ? 'Fee not specified'
                : 'Consultation fee ' + String.valueOf(doctor.Consultation_Fee__c);
            String availability = String.isBlank(doctor.Availability_Status__c)
                ? 'Availability not specified'
                : doctor.Availability_Status__c;
            String maximum = doctor.Max_Daily_Appointments__c == null
                ? 'Daily appointment limit not specified'
                : 'Maximum ' + String.valueOf(doctor.Max_Daily_Appointments__c) + ' appointments per day';
            details.add(
                doctor.Name + ' - ' + departmentName + ' - ' + specialization + ' - ' +
                experience + ' - ' + fee + ' - ' + availability + ' - ' + maximum
            );
        }
        return 'Doctor information: ' + String.join(details, '; ') + '.';
    }

    private static String facilityAnswer(String searchTerm) {
        String pattern = String.isBlank(searchTerm) ? '%' : '%' + searchTerm + '%';
        List<Ward__c> wards = [
            SELECT Ward_Type__c, Status__c
            FROM Ward__c
            WHERE Ward_Type__c LIKE :pattern
            WITH SYSTEM_MODE
            ORDER BY Ward_Type__c
            LIMIT 100
        ];
        List<Room__c> rooms = [
            SELECT Room_Type__c, Capacity__c, Available_Beds__c, Price__c,
                   Status__c, Ward__r.Ward_Type__c
            FROM Room__c
            WHERE Room_Type__c LIKE :pattern OR Ward__r.Ward_Type__c LIKE :pattern
            WITH SYSTEM_MODE
            ORDER BY Room_Type__c
            LIMIT 200
        ];
        if (wards.isEmpty() && rooms.isEmpty()) {
            return String.isBlank(searchTerm)
                ? 'No ward or room information is currently listed. Please check again later.'
                : 'No, ' + searchTerm + ' is not currently listed in the hospital facilities directory. Please check again later.';
        }

        Set<String> wardDescriptions = new Set<String>();
        for (Ward__c ward : wards) {
            if (!String.isBlank(ward.Ward_Type__c)) {
                wardDescriptions.add(
                    ward.Ward_Type__c + (String.isBlank(ward.Status__c) ? '' : ' (' + ward.Status__c + ')')
                );
            }
        }

        Map<String, Decimal> capacityByType = new Map<String, Decimal>();
        Map<String, Decimal> availableByType = new Map<String, Decimal>();
        Map<String, Set<Decimal>> pricesByType = new Map<String, Set<Decimal>>();
        for (Room__c room : rooms) {
            String roomType = String.isBlank(room.Room_Type__c) ? 'Unspecified room type' : room.Room_Type__c;
            capacityByType.put(
                roomType,
                (capacityByType.containsKey(roomType) ? capacityByType.get(roomType) : 0) +
                (room.Capacity__c == null ? 0 : room.Capacity__c)
            );
            availableByType.put(
                roomType,
                (availableByType.containsKey(roomType) ? availableByType.get(roomType) : 0) +
                (room.Available_Beds__c == null ? 0 : room.Available_Beds__c)
            );
            if (!pricesByType.containsKey(roomType)) pricesByType.put(roomType, new Set<Decimal>());
            if (room.Price__c != null) pricesByType.get(roomType).add(room.Price__c);
        }

        List<String> roomDescriptions = new List<String>();
        List<String> roomTypes = new List<String>(capacityByType.keySet());
        roomTypes.sort();
        for (String roomType : roomTypes) {
            List<Decimal> prices = new List<Decimal>(pricesByType.get(roomType));
            prices.sort();
            String priceDescription = prices.isEmpty()
                ? 'price not configured'
                : prices.size() == 1
                    ? 'USD ' + String.valueOf(prices[0]) + ' per day'
                    : 'USD ' + String.valueOf(prices[0]) + ' to USD ' +
                        String.valueOf(prices[prices.size() - 1]) + ' per day';
            roomDescriptions.add(
                roomType + ' - bed capacity ' + String.valueOf(capacityByType.get(roomType)) +
                ', currently available ' + String.valueOf(availableByType.get(roomType)) +
                ', ' + priceDescription
            );
        }

        List<String> parts = new List<String>();
        if (!wardDescriptions.isEmpty()) {
            List<String> wardList = new List<String>(wardDescriptions);
            wardList.sort();
            parts.add('Ward types: ' + String.join(wardList, ', '));
        }
        if (!roomDescriptions.isEmpty()) parts.add('Room options: ' + String.join(roomDescriptions, '; '));
        return String.join(parts, '. ') + '.';
    }

    private static String admissionFeeAnswer() {
        List<Admission__c> records = [
            SELECT Admission_Fee__c
            FROM Admission__c
            WHERE Admission_Fee__c != null
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (records.isEmpty() || records[0].Admission_Fee__c == null) {
            return 'No standard admission fee is currently configured. Please check again later.';
        }
        return 'The currently configured standard admission fee is ' +
            String.valueOf(records[0].Admission_Fee__c) + ' in the hospital billing currency.';
    }

    private static String insuranceAnswer(String searchTerm) {
        List<Insurance_Company__c> records = [
            SELECT Name
            FROM Insurance_Company__c
            WHERE Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 100
        ];
        if (!String.isBlank(searchTerm)) {
            String normalizedSearch = normalize(searchTerm);
            List<Insurance_Company__c> matches = new List<Insurance_Company__c>();
            for (Insurance_Company__c company : records) {
                if (matchesSearch(normalizedSearch, company.Name)) matches.add(company);
            }
            if (matches.isEmpty()) {
                return 'No, ' + searchTerm +
                    ' is not currently listed as an accepted insurance company. Please check again later.';
            }
            List<String> matchedNames = new List<String>();
            for (Insurance_Company__c company : matches) matchedNames.add(company.Name);
            return 'Yes, the hospital currently accepts ' + String.join(matchedNames, ', ') + '.';
        }
        if (records.isEmpty()) {
            return 'No active insurance companies are currently listed. Please check again later.';
        }
        List<String> names = new List<String>();
        for (Insurance_Company__c company : records) names.add(company.Name);
        return 'Accepted insurance companies: ' + String.join(names, ', ') + '.';
    }

    private static String subsidyAnswer() {
        return 'Patient category subsidy policy: Normal - 0%; Civil Servant - 50%; ' +
            'Armed Professional - 40%; Hospital Employee - 20%. ' +
            'The applicable subsidy is subject to hospital billing eligibility verification.';
    }

    private static String hospitalInfoAnswer(String informationType) {
        String key = normalize(informationType).replace(' ', '_');
        Map<String, String> allowedKeys = new Map<String, String>{
            'timings' => 'Hospital_Timings',
            'location' => 'Hospital_Location',
            'contact' => 'Hospital_Contact_Number',
            'contact_number' => 'Hospital_Contact_Number',
            'ambulance' => 'Ambulance_Number',
            'ambulance_number' => 'Ambulance_Number'
        };
        if (!allowedKeys.containsKey(key)) return FALLBACK;
        PH_Hospital_Information__mdt information =
            PH_Hospital_Information__mdt.getInstance(allowedKeys.get(key));
        if (information == null || information.Active__c != true || String.isBlank(information.Value__c)) {
            return FALLBACK;
        }
        return information.MasterLabel + ': ' + information.Value__c;
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    private static String clean(String value) {
        if (String.isBlank(value)) return null;
        String cleaned = value.trim();
        return cleaned.length() > 80 ? cleaned.substring(0, 80) : cleaned;
    }

    private static Boolean matchesSearch(String normalizedSearch, String candidate) {
        if (String.isBlank(normalizedSearch) || String.isBlank(candidate)) return false;
        String normalizedCandidate = normalize(candidate);
        return normalizedSearch.contains(normalizedCandidate) ||
            normalizedCandidate.contains(normalizedSearch);
    }
}

public without sharing class AppointmentBookingInvocableListDoctors {
    public class Request {
        @InvocableVariable(
            label='Portal User Id'
            description='Authenticated patient User Id. Auto-mapped from customerId when blank.'
        )
        public String portalUserId;

        @InvocableVariable(
            label='Department Name'
            description='Required. Medical department such as Cardiology or General Medicine. OPD is an appointment type, not a department.'
            required=true
        )
        public String departmentName;

        @InvocableVariable(
            label='Appointment Date'
            description='Optional date YYYY-MM-DD to filter doctors available that day.'
        )
        public String appointmentDate;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean isSuccess;

        @InvocableVariable(
            label='Doctors Text'
            description='Numbered list of doctors in the department. Present to the patient.'
        )
        public String doctorsText;

        @InvocableVariable(label='Doctor Count')
        public Integer doctorCount;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='List Department Doctors'
        description='Returns doctors available in a medical department so the patient can choose one or say any doctor.'
        category='Appointment Management'
    )
    public static List<Response> listDoctors(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.isSuccess = false;
            res.doctorCount = 0;
            try {
                AppointmentBookingInvocable.resolvePatientId(req.portalUserId);
                Date targetDate = String.isBlank(req.appointmentDate)
                    ? null
                    : AppointmentBookingInvocable.parseDate(req.appointmentDate);
                List<String> names = AppointmentBookingService.listDoctorNamesForDepartment(
                    req.departmentName,
                    targetDate
                );
                res.isSuccess = true;
                res.doctorCount = names.size();
                res.doctorsText = AppointmentBookingService.formatDoctorsForDepartment(
                    req.departmentName,
                    targetDate
                );
            } catch (Exception ex) {
                res.errorMessage = ex.getMessage();
                res.doctorsText = ex.getMessage();
            }
            responses.add(res);
        }
        return responses;
    }
}
public with sharing class PH_CreateTicketOnceAction {
    public class Request {
        @InvocableVariable(required=true label='First Question' description='The first substantive user question in this conversation')
        public String firstQuestion;

        @InvocableVariable(required=true label='Category' description='Appointment, Admission, or General')
        public String category;

        @InvocableVariable(label='Patient Id' description='Optional authenticated patient record Id. Leave blank for visitors.')
        public String patientId;

        @InvocableVariable(label='Conversation Key' description='Messaging session RoutableId. Always map from the agent session when available.')
        public String conversationKey;
    }

    public class Response {
        @InvocableVariable(label='Ticket Created')
        public Boolean ticketCreated;

        @InvocableVariable(label='Ticket Already Existed')
        public Boolean ticketAlreadyExisted;

        @InvocableVariable(label='Result Message')
        public String message;
    }

    @InvocableMethod(
        label='Create Patient Helpdesk Ticket Once'
        description='Calls the existing HelpDesk Ticket Flow at most once per messaging conversation.'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            responses.add(processRequest(request));
        }
        return responses;
    }

    private static Response processRequest(Request request) {
        Response response = new Response();
        response.ticketCreated = false;
        response.ticketAlreadyExisted = false;

        if (request == null || String.isBlank(request.firstQuestion)) {
            response.message = 'A first question is required before creating a helpdesk ticket.';
            return response;
        }

        String category = normalizeCategory(request.category);
        String question = request.firstQuestion.trim();
        if (question.length() > 2000) question = question.substring(0, 2000);
        String conversationKey = buildConversationKey(request.conversationKey, question);
        String marker = '[Agent Conversation: ' + conversationKey + ']';
        List<Helpdesk_Ticket__c> recentTickets = [
            SELECT Id, Description__c
            FROM Helpdesk_Ticket__c
            WHERE CreatedById = :UserInfo.getUserId()
            AND CreatedDate = TODAY
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
        for (Helpdesk_Ticket__c ticket : recentTickets) {
            if (ticket.Description__c != null && ticket.Description__c.contains(marker)) {
                response.ticketAlreadyExisted = true;
                response.message = 'The conversation already has a helpdesk ticket.';
                return response;
            }
        }

        Map<String, Object> inputs = new Map<String, Object>{
            'Category' => category,
            'FirstQuestion' => question + '\n' + marker,
            'PatientId' => String.isBlank(request.patientId) ? null : request.patientId
        };
        Flow.Interview.HelpDesk_Ticket_Flow interview =
            new Flow.Interview.HelpDesk_Ticket_Flow(inputs);
        interview.start();

        Object createdValue = interview.getVariableValue('TicketCreated');
        response.ticketCreated = createdValue instanceof Boolean && (Boolean) createdValue;
        response.message = response.ticketCreated
            ? 'A helpdesk ticket was created for this conversation.'
            : 'The helpdesk ticket flow did not confirm ticket creation.';
        return response;
    }

    private static String normalizeCategory(String value) {
        if (String.isBlank(value)) return 'General';
        String normalized = value.trim().toLowerCase();
        if (normalized == 'appointment') return 'Appointment';
        if (normalized == 'admission') return 'Admission';
        return 'General';
    }

    private static String buildConversationKey(String suppliedKey, String question) {
        if (!String.isBlank(suppliedKey)) {
            String cleaned = suppliedKey.replaceAll('[^A-Za-z0-9_-]', '');
            if (!String.isBlank(cleaned)) return cleaned.left(80);
        }
        Blob digest = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(UserInfo.getUserId() + '|' + Date.today().format() + '|' + question)
        );
        return EncodingUtil.convertToHex(digest).left(40);
    }
}

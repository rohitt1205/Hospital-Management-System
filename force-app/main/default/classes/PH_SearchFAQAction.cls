public without sharing class PH_SearchFAQAction {
    public class Request {
        @InvocableVariable(label='Search Term' description='The question, topic, or category to search for in the FAQs.' required=false)
        public String searchTerm;
    }

    public class Response {
        @InvocableVariable(label='FAQ Text' description='The matching questions and answers.')
        public String faqText;

        @InvocableVariable(label='Found' description='Whether any matching FAQs were found.')
        public Boolean found;
    }

    @InvocableMethod(
        label='Search Patient FAQs'
        description='Searches the hospital database for patient FAQs matching a search term, topic, or category. Returns the matching questions and answers.'
    )
    public static List<Response> searchFAQs(List<Request> requests) {
        List<Response> responses = new List<Response>();
        
        // Retrieve all active FAQs since the database is small (15 records standard)
        List<FAQ__c> allFaqs = [
            SELECT Question__c, Answer__c, Category__c
            FROM FAQ__c
            WHERE Is_Active__c = true
            ORDER BY Category__c, Name
        ];
        
        for (Request req : requests) {
            Response resp = new Response();
            String term = req != null && req.searchTerm != null ? req.searchTerm.trim().toLowerCase() : '';
            
            List<FAQ__c> matchedFaqs = new List<FAQ__c>();
            if (String.isBlank(term)) {
                // If search term is empty, return up to 10 FAQs
                for (Integer i = 0; i < Math.min(10, allFaqs.size()); i++) {
                    matchedFaqs.add(allFaqs[i]);
                }
            } else {
                // In-memory filter on category, question, and answer
                for (FAQ__c faq : allFaqs) {
                    Boolean matches = false;
                    if (faq.Category__c != null && faq.Category__c.toLowerCase().contains(term)) {
                        matches = true;
                    }
                    if (faq.Question__c != null && faq.Question__c.toLowerCase().contains(term)) {
                        matches = true;
                    }
                    if (faq.Answer__c != null && faq.Answer__c.toLowerCase().contains(term)) {
                        matches = true;
                    }
                    if (matches) {
                        matchedFaqs.add(faq);
                    }
                }
                
                // Limit to 5 matches
                if (matchedFaqs.size() > 5) {
                    List<FAQ__c> limited = new List<FAQ__c>();
                    for (Integer i = 0; i < 5; i++) {
                        limited.add(matchedFaqs[i]);
                    }
                    matchedFaqs = limited;
                }
            }
            
            if (matchedFaqs.isEmpty()) {
                resp.found = false;
                resp.faqText = 'No matching FAQs found for: ' + term;
            } else {
                resp.found = true;
                List<String> entries = new List<String>();
                for (FAQ__c faq : matchedFaqs) {
                    entries.add('Category: ' + faq.Category__c + '\nQuestion: ' + faq.Question__c + '\nAnswer: ' + faq.Answer__c);
                }
                resp.faqText = String.join(entries, '\n\n');
            }
            responses.add(resp);
        }
        
        return responses;
    }
}

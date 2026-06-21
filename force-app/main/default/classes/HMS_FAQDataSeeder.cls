public without sharing class HMS_FAQDataSeeder {
    public static void seedFAQs() {
        // Prevent duplicate seeding
        if ([SELECT Count() FROM FAQ__c] > 0) {
            System.debug('FAQs already seeded. Skipping.');
            return;
        }
        
        List<FAQ__c> faqs = new List<FAQ__c>();
        
        // 1. Admissions
        faqs.add(new FAQ__c(
            Question__c = 'What documents and details do I need to prepare for my upcoming inpatient admission?',
            Answer__c = 'For inpatient admissions, please bring a valid government-issued photo identity card (Aadhaar Card, Passport, or Driver\'s License), your hospital reference card (if previously registered), doctor\'s referral/recommendation letters, and all recent medical reports. If you plan to claim insurance, also bring your original health insurance card and pre-authorization approvals.',
            Category__c = 'Admissions',
            Is_Active__c = true
        ));
        faqs.add(new FAQ__c(
            Question__c = 'What is the standard check-in and room assignment process for a planned hospital admission?',
            Answer__c = 'On the day of admission, please report to the Admission Desk at the main lobby at least two hours before your scheduled time. Our staff will verify your identification, complete the consent paperwork, allocate a room based on your category and availability, and escort you to the ward.',
            Category__c = 'Admissions',
            Is_Active__c = true
        ));
        faqs.add(new FAQ__c(
            Question__c = 'What are the rules regarding personal belongings, medications, and valuables during my hospital stay?',
            Answer__c = 'We advise patients to leave high-value personal items, large amounts of cash, and jewelry at home. Please bring your current ongoing medications in their original packaging to show the treating doctor, but do not take them without consulting our ward nursing staff.',
            Category__c = 'Admissions',
            Is_Active__c = true
        ));
        
        // 2. Appointments
        faqs.add(new FAQ__c(
            Question__c = 'How can I book, reschedule, or cancel a consultation appointment with a specialist doctor?',
            Answer__c = 'You can schedule, reschedule, or cancel appointments directly through the online Patient Portal, by calling our central patient helpdesk (+91-9910154408), or by utilizing our WhatsApp bot assistant. Please reschedule or cancel at least 24 hours prior to the slot to allow other patients to seek consultation.',
            Category__c = 'Appointments',
            Is_Active__c = true
        ));
        faqs.add(new FAQ__c(
            Question__c = 'What is the process for walk-in consultations if I do not have a pre-booked appointment?',
            Answer__c = 'Walk-in consultations are available for general medicine and select specialties, subject to doctor availability and slot vacancies. Upon arrival at the OPD reception desk, you will be registered and placed in the queue; however, pre-booked appointments will be prioritized.',
            Category__c = 'Appointments',
            Is_Active__c = true
        ));
        faqs.add(new FAQ__c(
            Question__c = 'Why is my appointment showing as pending or under review in the Patient Portal?',
            Answer__c = 'Appointments require doctor availability verification and department approval. If an appointment is under review, our clinic coordinators are validating the doctor\'s schedule. Once confirmed, you will receive an automated WhatsApp confirmation message.',
            Category__c = 'Appointments',
            Is_Active__c = true
        ));
        
        // 3. Billing
        faqs.add(new FAQ__c(
            Question__c = 'What are the payment options and payment modes accepted for settling my final medical bills?',
            Answer__c = 'We accept payments via major credit/debit cards (Visa, MasterCard, RuPay), Net Banking, UPI (Unified Payments Interface), UPI QR codes, and online gateways (like Razorpay). Cash payments are accepted at the billing counters up to limits specified by tax regulations.',
            Category__c = 'Billing',
            Is_Active__c = true
        ));
        faqs.add(new FAQ__c(
            Question__c = 'How does the cashless health insurance claim and coverage verification process work?',
            Answer__c = 'If your policy is with an approved insurance company, submit your e-card and policy details to our TPA (Third Party Administrator) desk at least 48 hours prior to planned admission. The TPA desk coordinates with the insurer to obtain pre-authorization. Any non-billable deductions or co-pays must be settled directly by the patient before discharge.',
            Category__c = 'Billing',
            Is_Active__c = true
        ));
        faqs.add(new FAQ__c(
            Question__c = 'What happens if my final invoice has a discount, and how is the net payable amount calculated?',
            Answer__c = 'The net payable amount is calculated as Gross Amount minus any Insurance Cover minus Patient Category Discounts (e.g., employee, civil servant, or armed professional discounts) minus Non-Billable Deductions. Patient discounts are applied only to the base billing components after insurance deductions.',
            Category__c = 'Billing',
            Is_Active__c = true
        ));
        
        // 4. Emergency
        faqs.add(new FAQ__c(
            Question__c = 'What constitutes a medical emergency and how do I contact the emergency services?',
            Answer__c = 'A medical emergency includes severe chest pain, breathing difficulty, heavy bleeding, sudden weakness/stroke symptoms, unconsciousness, or major trauma. Our Trauma and Emergency Center operates 24/7. You can contact our emergency ambulance hotline at +91-9910154408 immediately.',
            Category__c = 'Emergency',
            Is_Active__c = true
        ));
        faqs.add(new FAQ__c(
            Question__c = 'What is the admission and priority triage process for emergency patients?',
            Answer__c = 'Patients arriving at the Emergency Department are immediately triaged by a clinical team based on severity, not arrival order. Life-threatening cases are treated first. Formal admission paperwork and billing details can be completed by a relative or guardian after the patient has been stabilized.',
            Category__c = 'Emergency',
            Is_Active__c = true
        ));
        
        // 5. Visitors
        faqs.add(new FAQ__c(
            Question__c = 'What are the general visiting hours and policies for patient relatives?',
            Answer__c = 'General visiting hours for inpatient wards are from 11:00 AM to 1:00 PM and 5:00 PM to 7:00 PM daily. Only one visitor is permitted per patient at a time. Visitors must obtain a valid visitor pass from the reception counter and maintain silence in the patient care areas.',
            Category__c = 'Visitors',
            Is_Active__c = true
        ));
        faqs.add(new FAQ__c(
            Question__c = 'Are there specific visitor rules and restrictions for intensive care units (ICUs)?',
            Answer__c = 'ICU visiting hours are highly restricted (strictly 12:00 PM to 1:00 PM for 5 minutes per patient) to prevent infection risk and ensure patient recovery. Only immediate family members with sterile protective gowns and masks are permitted inside the ICU wards.',
            Category__c = 'Visitors',
            Is_Active__c = true
        ));
        
        // 6. General
        faqs.add(new FAQ__c(
            Question__c = 'How can I obtain a copy of my discharge summary and complete final report after discharge?',
            Answer__c = 'Your finalized medical report and discharge summary are uploaded to your Patient Portal dashboard within 24 hours of discharge. You will also receive a secure download link via WhatsApp. Physical copies can be collected from the Medical Records Department (MRD) by showing your patient ID.',
            Category__c = 'General',
            Is_Active__c = true
        ));
        faqs.add(new FAQ__c(
            Question__c = 'What is the hospital visitor parking availability, fees, and location?',
            Answer__c = 'On-site parking is available for visitors and patients in the basement and ground level parking bays. Parking is free for patients undergoing emergency care or planned admissions (validated at the billing desk). General visitors will be charged a standard hourly parking fee.',
            Category__c = 'General',
            Is_Active__c = true
        ));
        
        insert faqs;
        System.debug('Successfully seeded ' + faqs.size() + ' FAQs.');
    }
}

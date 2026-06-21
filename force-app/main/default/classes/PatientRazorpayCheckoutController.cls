/**
 * Visualforce-hosted Razorpay checkout for the patient portal.
 * LWC cannot call window.Razorpay under Lightning Web Security; this page runs outside LWS.
 */
public without sharing class PatientRazorpayCheckoutController {
    public String keyId { get; private set; }
    public String orderId { get; private set; }
    public Long amountPaise { get; private set; }
    public String checkoutCurrency { get; private set; }
    public String merchantName { get; private set; }
    public String invoiceLabel { get; private set; }
    public String patientName { get; private set; }
    public String patientEmail { get; private set; }
    public String patientPhone { get; private set; }
    public String patientIdStr { get; private set; }
    public String invoiceIdStr { get; private set; }
    public Boolean ready { get; private set; }
    public String errorMessage { get; private set; }

    public PatientRazorpayCheckoutController() {
        ready = false;
        merchantName = 'Hospital Patient Portal';
        checkoutCurrency = 'INR';
        try {
            Map<String, String> params = ApexPages.currentPage().getParameters();
            Id patientId = parseId(params.get('patientId'));
            Id invoiceId = parseId(params.get('invoiceId'));
            if (patientId == null || invoiceId == null) {
                throw new AuraHandledException('Patient and invoice are required to start payment.');
            }

            Patient__c linkedPatient = PatientPortalLinkService.resolveForRunningUser();
            if (linkedPatient == null || linkedPatient.Id != patientId) {
                throw new AuraHandledException('You are not authorized to pay this invoice.');
            }

            Map<String, Object> billing = HMS_PaymentController.getPatientBillingDetails(invoiceId);
            Map<String, Object> order = HMS_PaymentController.createRazorpayOrder(patientId, invoiceId);

            keyId = HMS_PaymentController.getRazorpayKeyId();
            orderId = (String) order.get('orderId');
            amountPaise = (Long) order.get('amountPaise');
            invoiceLabel = 'Invoice ' + String.valueOf(order.get('invoiceName'));
            patientName = (String) billing.get('patientName');
            patientEmail = (String) billing.get('patientEmail');
            patientPhone = (String) billing.get('patientPhone');
            patientIdStr = String.valueOf(patientId);
            invoiceIdStr = String.valueOf(invoiceId);

            if (String.isBlank(orderId) || amountPaise == null || amountPaise <= 0) {
                throw new AuraHandledException('Unable to prepare a Razorpay order for this invoice.');
            }

            ready = true;
        } catch (Exception e) {
            errorMessage = e.getMessage();
        }
    }

    @RemoteAction
    public static Map<String, Object> completePayment(
        String patientId,
        String invoiceId,
        String razorpayPaymentId,
        String razorpayOrderId,
        String razorpaySignature,
        String paymentMode
    ) {
        try {
            Patient__c linkedPatient = PatientPortalLinkService.resolveForRunningUser();
            if (linkedPatient == null || String.valueOf(linkedPatient.Id) != patientId) {
                throw new AuraHandledException('You are not authorized to record this payment.');
            }

            String paymentRecordId = HMS_PaymentController.recordSuccessfulPayment(
                Id.valueOf(patientId),
                Id.valueOf(invoiceId),
                razorpayPaymentId,
                razorpayOrderId,
                razorpaySignature,
                String.isBlank(paymentMode) ? 'Online' : paymentMode
            );
            return new Map<String, Object>{
                'success' => true,
                'paymentId' => paymentRecordId
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => e.getMessage()
            };
        }
    }

    private static Id parseId(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return Id.valueOf(raw);
        } catch (Exception e) {
            return null;
        }
    }
}
public without sharing class FinalReportPdfController {
    public FinalReportController.ReportWrapper data { get; set; }
    public Final_Report__c report { get; set; }
    public Patient__c patient { get; set; }
    public Admission__c admission { get; set; }
    public Appointment__c appointment { get; set; }
    public List<Lab_Result__c> labResults { get; set; }
    public List<FinalReportController.PrescriptionLineItemWrapper> prescriptionLineItems { get; set; }
    public List<Invoice_Line_Item__c> invoiceLineItems { get; set; }
    public Invoice__c invoice { get; set; }
    
    // Formatted INR Amounts
    public String grossInr { get; set; }
    public String discountInr { get; set; }
    public String insuranceInr { get; set; }
    public String nonBillableInr { get; set; }
    public String netPayableInr { get; set; }
    
    public Boolean hasAppointment { get; set; }
    public Boolean hasAdmission { get; set; }
    public Boolean hasLabs { get; set; }
    public Boolean hasPrescriptions { get; set; }
    public Boolean hasInvoiceLineItems { get; set; }
    public Boolean hasInvoice { get; set; }
    
    public class FormattedLineItem {
        public String chargeType { get; set; }
        public String description { get; set; }
        public Decimal quantity { get; set; }
        public String unitPriceInr { get; set; }
        public String lineTotalInr { get; set; }
    }
    
    public List<FormattedLineItem> formattedInvoiceLineItems { get; set; }
    
    public FinalReportPdfController() {
        Id reportId = ApexPages.currentPage().getParameters().get('id');
        if (reportId == null) {
            return;
        }
        
        this.data = FinalReportController.getReportDetails(reportId);
        if (this.data != null) {
            this.report = this.data.report;
            this.patient = this.data.patient;
            this.admission = this.data.admission;
            this.appointment = this.data.appointment;
            this.labResults = this.data.labResults;
            this.prescriptionLineItems = this.data.prescriptionLineItems;
            this.invoiceLineItems = this.data.invoiceLineItems;
            this.invoice = this.data.invoice;
            
            this.hasAppointment = (this.appointment != null);
            this.hasAdmission = (this.admission != null);
            this.hasLabs = (this.labResults != null && !this.labResults.isEmpty());
            this.hasPrescriptions = (this.prescriptionLineItems != null && !this.prescriptionLineItems.isEmpty());
            this.hasInvoiceLineItems = (this.invoiceLineItems != null && !this.invoiceLineItems.isEmpty());
            this.hasInvoice = (this.invoice != null);
            
            if (this.hasInvoice) {
                this.grossInr = formatCurrency(this.invoice.Gross_Amount__c);
                this.discountInr = formatCurrency(this.invoice.Discount_Amount__c);
                this.insuranceInr = formatCurrency(this.invoice.Insurance_Covered_Amount__c);
                this.nonBillableInr = formatCurrency(this.invoice.Non_Billable_Deduction__c);
                this.netPayableInr = formatCurrency(this.invoice.Net_Payable__c);
            }
            
            this.formattedInvoiceLineItems = new List<FormattedLineItem>();
            if (this.hasInvoiceLineItems) {
                for (Invoice_Line_Item__c item : this.invoiceLineItems) {
                    FormattedLineItem fli = new FormattedLineItem();
                    fli.chargeType = item.Charge_Type__c != null ? item.Charge_Type__c : 'N/A';
                    fli.description = item.Description__c != null ? item.Description__c : fli.chargeType;
                    fli.quantity = item.Quantity__c != null ? item.Quantity__c : 0;
                    fli.unitPriceInr = formatCurrency(item.Unit_Price__c);
                    fli.lineTotalInr = formatCurrency(item.Line_Total__c);
                    this.formattedInvoiceLineItems.add(fli);
                }
            }
        }
    }
    
    private String formatCurrency(Decimal usdAmount) {
        Decimal numericAmount = usdAmount != null ? usdAmount : 0;
        Decimal inrAmount = numericAmount * 92;
        return '₹' + inrAmount.setScale(2).format();
    }
}
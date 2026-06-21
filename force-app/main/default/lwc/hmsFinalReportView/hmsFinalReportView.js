import { LightningElement, api, wire } from 'lwc';
import getReportDetails from '@salesforce/apex/FinalReportController.getReportDetails';
import sendReportWhatsApp from '@salesforce/apex/FinalReportController.sendReportWhatsApp';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

const INR_PER_USD = 92;
const INR_FORMATTER = new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
});

function formatInr(usdAmount) {
    const numericAmount = Number(usdAmount || 0);
    return INR_FORMATTER.format(numericAmount * INR_PER_USD);
}

export default class HmsFinalReportView extends LightningElement {
    @api recordId;
    
    reportData;
    error;
    isLoading = true;
    isSending = false;
    wiredRecordResult;

    @wire(getReportDetails, { reportId: '$recordId' })
    wiredRecord(result) {
        this.wiredRecordResult = result;
        if (result.data) {
            const rawData = result.data;
            this.reportData = {
                ...rawData,
                labResults: rawData.labResults ? rawData.labResults.map(lab => ({
                    ...lab,
                    testName: lab.Lab_Test__r ? lab.Lab_Test__r.Name : 'N/A'
                })) : [],
                prescriptionLineItems: rawData.prescriptionLineItems ? rawData.prescriptionLineItems.map(pli => ({
                    ...pli,
                    durationText: pli.durationDays ? `${pli.durationDays} Days` : 'N/A',
                    instructionsText: pli.instructions || 'N/A',
                    totalPriceInr: formatInr(pli.totalPrice)
                })) : [],
                invoiceLineItems: rawData.invoiceLineItems ? rawData.invoiceLineItems.map(item => ({
                    ...item,
                    chargeType: item.Charge_Type__c || 'N/A',
                    description: item.Description__c || 'N/A',
                    unitPrice: item.Unit_Price__c !== undefined && item.Unit_Price__c !== null ? item.Unit_Price__c : 0,
                    lineTotal: item.Line_Total__c !== undefined && item.Line_Total__c !== null ? item.Line_Total__c : 0,
                    unitPriceInr: formatInr(item.Unit_Price__c),
                    lineTotalInr: formatInr(item.Line_Total__c),
                    Quantity__c: item.Quantity__c !== undefined && item.Quantity__c !== null ? item.Quantity__c : 0
                })) : [],
                invoice: rawData.invoice ? {
                    ...rawData.invoice,
                    Gross_Amount__c: rawData.invoice.Gross_Amount__c !== undefined && rawData.invoice.Gross_Amount__c !== null ? rawData.invoice.Gross_Amount__c : 0,
                    Insurance_Covered_Amount__c: rawData.invoice.Insurance_Covered_Amount__c !== undefined && rawData.invoice.Insurance_Covered_Amount__c !== null ? rawData.invoice.Insurance_Covered_Amount__c : 0,
                    Discount_Amount__c: rawData.invoice.Discount_Amount__c !== undefined && rawData.invoice.Discount_Amount__c !== null ? rawData.invoice.Discount_Amount__c : 0,
                    Non_Billable_Deduction__c: rawData.invoice.Non_Billable_Deduction__c !== undefined && rawData.invoice.Non_Billable_Deduction__c !== null ? rawData.invoice.Non_Billable_Deduction__c : 0,
                    Net_Payable__c: rawData.invoice.Net_Payable__c !== undefined && rawData.invoice.Net_Payable__c !== null ? rawData.invoice.Net_Payable__c : 0,
                    grossAmountInr: formatInr(rawData.invoice.Gross_Amount__c),
                    insuranceCoveredAmountInr: formatInr(rawData.invoice.Insurance_Covered_Amount__c),
                    discountAmountInr: formatInr(rawData.invoice.Discount_Amount__c),
                    nonBillableDeductionInr: formatInr(rawData.invoice.Non_Billable_Deduction__c),
                    netPayableInr: formatInr(rawData.invoice.Net_Payable__c)
                } : null
            };
            this.error = undefined;
            this.isLoading = false;
        } else if (result.error) {
            this.error = result.error;
            this.reportData = undefined;
            this.isLoading = false;
        }
    }

    get appointmentDoctorName() {
        return this.reportData && this.reportData.appointment && this.reportData.appointment.Doctor__r 
            ? this.reportData.appointment.Doctor__r.Name 
            : 'N/A';
    }

    get treatingDoctorName() {
        return this.reportData && this.reportData.report && this.reportData.report.Doctor__r 
            ? this.reportData.report.Doctor__r.Name 
            : 'N/A';
    }

    get roomName() {
        return this.reportData && this.reportData.admission && this.reportData.admission.Room__r 
            ? this.reportData.admission.Room__r.Name 
            : 'N/A';
    }

    get bedName() {
        return this.reportData && this.reportData.admission && this.reportData.admission.Bed__r 
            ? this.reportData.admission.Bed__r.Name 
            : 'N/A';
    }

    get hasReport() {
        return this.reportData && this.reportData.report;
    }

    get hasPatient() {
        return this.reportData && this.reportData.patient;
    }

    get hasAppointment() {
        return this.reportData && this.reportData.appointment;
    }

    get hasAdmission() {
        return this.reportData && this.reportData.admission;
    }

    get hasLabs() {
        return this.reportData && this.reportData.labResults && this.reportData.labResults.length > 0;
    }

    get hasPrescriptions() {
        return this.reportData && this.reportData.prescriptionLineItems && this.reportData.prescriptionLineItems.length > 0;
    }

    get hasInvoiceLineItems() {
        return this.reportData && this.reportData.invoiceLineItems && this.reportData.invoiceLineItems.length > 0;
    }

    get hasInvoice() {
        return this.reportData && this.reportData.invoice;
    }

    get statusClass() {
        if (!this.reportData || !this.reportData.report) return '';
        const status = this.reportData.report.Status__c;
        if (status === 'Finalized') return 'badge-finalized';
        if (status === 'Draft') return 'badge-draft';
        return 'badge-other';
    }

    get paymentStatusClass() {
        if (!this.reportData || !this.reportData.invoice) return '';
        const pStatus = this.reportData.invoice.Payment_Status__c;
        if (pStatus === 'Paid') return 'badge-paid';
        if (pStatus === 'Unpaid') return 'badge-unpaid';
        return 'badge-other';
    }

    handleSendWhatsApp() {
        this.isSending = true;
        sendReportWhatsApp({ reportId: this.recordId })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Final report summary sent successfully via WhatsApp!',
                        variant: 'success'
                    })
                );
                this.isSending = false;
            })
            .catch(error => {
                const errorMsg = error && error.body && error.body.message 
                    ? error.body.message 
                    : (error && error.message ? error.message : 'Unknown error occurred while sending');
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error sending report',
                        message: errorMsg,
                        variant: 'error'
                    })
                );
                this.isSending = false;
            });
    }

    handlePrint() {
        if (this.hasReport) {
            window.print();
        }
    }

    get errorMessage() {
        return this.error && this.error.body && this.error.body.message
            ? this.error.body.message
            : 'The report could not be loaded. Refresh the page and try again.';
    }

    get printDisabled() {
        return this.isLoading || !this.hasReport;
    }
}
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';

import getPatientBillingDetails from '@salesforce/apex/HMS_PaymentController.getPatientBillingDetails';
import getRazorpayKeyId from '@salesforce/apex/HMS_PaymentController.getRazorpayKeyId';
import createRazorpayOrder from '@salesforce/apex/HMS_PaymentController.createRazorpayOrder';
import recordSuccessfulPayment from '@salesforce/apex/HMS_PaymentController.recordSuccessfulPayment';

export default class HmsPatientPaymentGateway extends LightningElement {
    @api recordId;

    @track billingDetails = {};
    @track keyId = '';
    @track isLoading = true;

    connectedCallback() {
        this.fetchBillingDetails();
        this.fetchKeyId();
        this.boundHandlePaymentMessage = this.handlePaymentMessage.bind(this);
        window.addEventListener('message', this.boundHandlePaymentMessage);
    }

    disconnectedCallback() {
        window.removeEventListener('message', this.boundHandlePaymentMessage);
    }

    fetchBillingDetails() {
        this.isLoading = true;
        getPatientBillingDetails({ patientId: this.recordId })
            .then(result => {
                this.billingDetails = result;
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error fetching billing details:', error);
                this.isLoading = false;
            });
    }

    fetchKeyId() {
        getRazorpayKeyId()
            .then(result => {
                this.keyId = result;
            })
            .catch(error => {
                console.error('Error fetching Razorpay Key ID:', error);
            });
    }

    get hasOutstanding() {
        return this.billingDetails && this.billingDetails.hasOutstanding;
    }

    get isPayDisabled() {
        return !this.hasOutstanding || !this.keyId || this.isLoading;
    }

    handlePayNow() {
        if (!this.keyId) {
            this.showToast('Error', 'Payment gateway not configured. Please contact administrator.', 'error');
            return;
        }
        if (!this.hasOutstanding) {
            this.showToast('Info', 'No outstanding balance found.', 'info');
            return;
        }

        const paymentWindow = window.open(
            'about:blank',
            'RazorpayPayment',
            'width=660,height=760,scrollbars=yes,resizable=yes,left=100,top=100'
        );
        if (!paymentWindow) {
            this.showToast('Popup blocked', 'Allow popups for Salesforce and try again.', 'error');
            return;
        }

        this.isLoading = true;
        createRazorpayOrder({
            patientId: this.billingDetails.patientId,
            invoiceId: this.billingDetails.invoiceId
        })
            .then(order => {
                if (!order || !order.orderId || Number(order.amountPaise) <= 0) {
                    throw new Error('Razorpay returned an incomplete payment order.');
                }

                const paymentContext = {
                    keyId: this.keyId,
                    patientName: this.billingDetails.patientName || '',
                    patientEmail: this.billingDetails.patientEmail || '',
                    patientPhone: this.billingDetails.patientPhone || '',
                    invoiceId: order.invoiceId || '',
                    invoiceName: order.invoiceName || '',
                    patientId: this.billingDetails.patientId,
                    paymentMode: 'Razorpay',
                    orderId: order.orderId,
                    amountPaise: Number(order.amountPaise),
                    displayAmount: order.amount
                };

                // Keep the complete checkout context in one parameter so Salesforce's
                // cross-domain Visualforce redirect cannot split the query string.
                const payload = encodeURIComponent(JSON.stringify(paymentContext));
                paymentWindow.location = '/apex/RazorpayPaymentGateway?payload=' + payload;
                this.isLoading = false;
            })
            .catch(error => {
                paymentWindow.close();
                this.isLoading = false;
                this.showToast(
                    'Unable to start payment',
                    error?.body?.message || error?.message || 'Razorpay order creation failed.',
                    'error'
                );
            });
    }

    handlePaymentMessage(event) {
        if (!event.data || !event.data.type) return;

        if (event.data.type === 'RAZORPAY_SUCCESS') {
            this.processPaymentSuccess(
                event.data.paymentId,
                event.data.orderId,
                event.data.signature,
                event.data.paymentMode
            );
        } else if (event.data.type === 'RAZORPAY_CANCELLED') {
            this.showToast('Cancelled', 'Payment was cancelled by user.', 'info');
        } else if (event.data.type === 'RAZORPAY_ERROR') {
            this.showToast('Error', 'Payment failed: ' + (event.data.message || 'Unknown error'), 'error');
        }
    }

    processPaymentSuccess(paymentId, orderId, signature, paymentMode) {
        this.isLoading = true;
        recordSuccessfulPayment({
            patientId: this.billingDetails.patientId,
            invoiceId: this.billingDetails.invoiceId,
            razorpayPaymentId: paymentId,
            razorpayOrderId: orderId,
            razorpaySignature: signature,
            paymentMode: paymentMode || 'Razorpay'
        })
            .then(() => {
                this.showToast('Success', 'Payment completed successfully. Invoice and payment records were updated.', 'success');
                this.fetchBillingDetails();
                this.dispatchEvent(new RefreshEvent());
            })
            .catch(error => {
                console.error('Error recording payment in Salesforce:', error);
                this.showToast(
                    'Payment verification failed',
                    error?.body?.message || `Razorpay payment ${paymentId} could not be verified.`,
                    'error'
                );
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
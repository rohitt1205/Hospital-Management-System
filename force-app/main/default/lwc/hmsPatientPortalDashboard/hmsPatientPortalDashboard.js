import { LightningElement, wire } from 'lwc';
import getPortalSummaryJson from '@salesforce/apex/HMSPatientPortalController.getPortalSummaryJson';

export default class HmsPatientPortalDashboard extends LightningElement {
    summary;
    error;

    @wire(getPortalSummaryJson)
    wiredSummary({ data, error }) {
        if (data) {
            try {
                const parsedData = JSON.parse(data);
                if (parsedData.appointments) {
                    const now = new Date().getTime();
                    parsedData.appointments = parsedData.appointments.map(app => {
                        const isOnline = app.appointmentType === 'Online' || app.appointmentType === 'Teleconsultation';
                        const apptTime = app.appointmentDateTime ? new Date(app.appointmentDateTime).getTime() : 0;
                        const isBeforeTime = now < apptTime;
                        
                        // Format date time for display
                        let formattedTime = '';
                        if (app.appointmentDateTime) {
                            const d = new Date(app.appointmentDateTime);
                            formattedTime = d.toLocaleString([], {
                                weekday: 'short',
                                month: 'short',
                                day: 'numeric',
                                hour: '2-digit',
                                minute: '2-digit'
                            });
                        }
                        
                        return {
                            ...app,
                            isOnline,
                            isBeforeTime,
                            formattedTime,
                            showJoinButton: isOnline && !isBeforeTime && app.joinUrl,
                            showPendingMessage: isOnline && isBeforeTime
                        };
                    });
                }
                this.summary = parsedData;
                this.error = undefined;
            } catch (err) {
                console.error('Error parsing dashboard summary:', err);
                this.error = 'Error loading patient portal dashboard data.';
            }
        } else if (error) {
            this.summary = undefined;
            this.error = error.body && error.body.message ? error.body.message : 'Unable to load patient data.';
        }
    }

    get hasAppointments() {
        return this.summary && this.summary.appointments && this.summary.appointments.length > 0;
    }

    get hasReports() {
        return this.summary && this.summary.reports && this.summary.reports.length > 0;
    }

    get hasInvoices() {
        return this.summary && this.summary.invoices && this.summary.invoices.length > 0;
    }

    get hasInsurance() {
        return this.summary && this.summary.insurancePolicies && this.summary.insurancePolicies.length > 0;
    }

    get formattedPendingAmount() {
        const amount = this.summary && this.summary.pendingAmount ? this.summary.pendingAmount : 0;
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            maximumFractionDigits: 0
        }).format(amount);
    }

    get insuranceStatus() {
        if (!this.hasInsurance) {
            return 'None';
        }
        const verified = this.summary.insurancePolicies.some((policy) => policy.verificationStatus === 'Verified');
        return verified ? 'Verified' : this.summary.insurancePolicies[0].verificationStatus;
    }
}
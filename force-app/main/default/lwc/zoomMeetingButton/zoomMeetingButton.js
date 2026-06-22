import { LightningElement, api, track } from 'lwc';
import getMeetingDetails from '@salesforce/apex/HMS_ZoomController.getMeetingDetails';

export default class ZoomMeetingButton extends LightningElement {
    @api recordId;
    @track meetingDetails;
    @track isBeforeTime = true;
    @track isLoading = true;
    
    intervalId;

    connectedCallback() {
        this.fetchMeetingData();
        // Check every 5 seconds to see if the appointment time has arrived
        this.intervalId = setInterval(() => {
            this.checkTime();
        }, 5000);
    }

    disconnectedCallback() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
        }
    }

    fetchMeetingData() {
        this.isLoading = true;
        getMeetingDetails({ appointmentId: this.recordId })
            .then(result => {
                if (result) {
                    this.meetingDetails = result;
                    this.checkTime();
                } else {
                    this.meetingDetails = null;
                }
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error fetching zoom meeting details:', error);
                this.meetingDetails = null;
                this.isLoading = false;
            });
    }

    checkTime() {
        if (!this.meetingDetails || !this.meetingDetails.appointmentDateTime) {
            this.isBeforeTime = false;
            return;
        }

        const apptTime = new Date(this.meetingDetails.appointmentDateTime).getTime();
        const now = new Date().getTime();
        this.isBeforeTime = now < apptTime;
    }

    get isOnlineAppointment() {
        if (!this.meetingDetails) return false;
        const type = this.meetingDetails.appointmentType;
        return type === 'Teleconsultation' || type === 'Online';
    }

    get meetingUrl() {
        if (!this.meetingDetails) return null;
        
        // Check if viewing from Experience Cloud portal
        const isPortal = window.location.pathname.includes('/s/');
        
        if (isPortal) {
            return this.meetingDetails.joinUrl;
        } else {
            // Internal staff/doctor context
            return this.meetingDetails.startUrl ? this.meetingDetails.startUrl : this.meetingDetails.joinUrl;
        }
    }

    get buttonLabel() {
        const isPortal = window.location.pathname.includes('/s/');
        return isPortal ? '🔑 Join Video Consultation' : '🚀 Start Video Consultation';
    }

    get titleText() {
        const isPortal = window.location.pathname.includes('/s/');
        return isPortal ? 'Your Teleconsultation' : 'Doctor Consultation Console';
    }

    get formattedAppointmentTime() {
        if (!this.meetingDetails || !this.meetingDetails.appointmentDateTime) {
            return '';
        }
        const apptTime = new Date(this.meetingDetails.appointmentDateTime);
        return apptTime.toLocaleString([], {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    handleJoinClick() {
        const url = this.meetingUrl;
        if (url) {
            window.open(url, '_blank');
        }
    }
}

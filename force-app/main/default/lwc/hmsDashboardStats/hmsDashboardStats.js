import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboardStats from '@salesforce/apex/HMSDashboardController.getDashboardStats';

const REFRESH_INTERVAL_MS = 30000; // auto-refresh every 30 seconds

export default class HmsDashboardStats extends LightningElement {
    @track stats = {};
    @track isLoading = true;
    @track hasError = false;

    _intervalId;

    get todayLabel() {
        return new Date().toLocaleDateString('en-IN', {
            weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
        });
    }

    connectedCallback() {
        this.loadStats();
        this._intervalId = setInterval(() => this.loadStats(), REFRESH_INTERVAL_MS);
    }

    disconnectedCallback() {
        if (this._intervalId) {
            clearInterval(this._intervalId);
        }
    }

    loadStats() {
        this.isLoading = true;
        this.hasError  = false;
        getDashboardStats()
            .then(data => {
                this.stats     = data;
                this.isLoading = false;
            })
            .catch(() => {
                this.hasError  = true;
                this.isLoading = false;
            });
    }

    refreshStats() {
        this.loadStats();
        this.dispatchEvent(new ShowToastEvent({
            title: 'Refreshed',
            message: 'Dashboard stats updated.',
            variant: 'success',
            mode: 'dismissable'
        }));
    }
}
import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getAvailableBeds from '@salesforce/apex/BedAvailabilityController.getAvailableBeds';

export default class AvailableBedPicker extends LightningElement {
    options = [];
    isLoading = false;
    @api selectedBedNumber;
    _roomId;
    _capacity;
    requestSequence = 0;

    @api
    get roomId() {
        return this._roomId;
    }
    set roomId(value) {
        if (this._roomId !== value) {
            this._roomId = value;
            this.loadOptions();
        }
    }

    @api
    get capacity() {
        return this._capacity;
    }
    set capacity(value) {
        const parsed = value === null || value === undefined || value === '' ? null : Number(value);
        if (this._capacity !== parsed) {
            this._capacity = parsed;
            this.loadOptions();
        }
    }

    get isDisabled() {
        return this.isLoading || (!this._roomId && !this._capacity) || this.options.length === 0;
    }

    get hasNoBeds() {
        return !this.isLoading && Boolean(this._roomId || this._capacity) && this.options.length === 0;
    }

    get placeholder() {
        if (this.isLoading) return 'Loading available beds...';
        if (!this._roomId && !this._capacity) return 'Select a room first';
        return 'Select an available bed';
    }

    async loadOptions() {
        const sequence = ++this.requestSequence;
        if (!this._roomId && !this._capacity) {
            this.options = [];
            this.clearSelection();
            return;
        }

        this.isLoading = true;
        try {
            const result = await getAvailableBeds({ roomId: this._roomId || null, capacity: this._capacity || null });
            if (sequence !== this.requestSequence) return;
            this.options = result || [];
            if (this.selectedBedNumber && !this.options.some(option => option.value === this.selectedBedNumber)) {
                this.clearSelection();
            }
        } catch (error) {
            if (sequence === this.requestSequence) {
                this.options = [];
                this.clearSelection();
            }
        } finally {
            if (sequence === this.requestSequence) this.isLoading = false;
        }
    }

    handleChange(event) {
        this.selectedBedNumber = event.detail.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedBedNumber', this.selectedBedNumber));
    }

    clearSelection() {
        if (this.selectedBedNumber) {
            this.selectedBedNumber = null;
            this.dispatchEvent(new FlowAttributeChangeEvent('selectedBedNumber', null));
        }
    }

    @api
    validate() {
        return this.selectedBedNumber
            ? { isValid: true }
            : { isValid: false, errorMessage: 'Select an available bed.' };
    }
}
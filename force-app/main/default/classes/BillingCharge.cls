public class BillingCharge {
    public String chargeType;
    public Id sourceRecordId;
    public String description;
    public Decimal quantity;
    public Decimal unitRate;
    public Boolean nonBillable;
    public Id clinicalServiceId;
    public Id medicineId;

    public BillingCharge(
        String chargeType,
        Id sourceRecordId,
        String description,
        Decimal quantity,
        Decimal unitRate
    ) {
        this.chargeType = chargeType;
        this.sourceRecordId = sourceRecordId;
        this.description = description;
        this.quantity = quantity == null ? 0 : quantity;
        this.unitRate = unitRate == null ? 0 : unitRate;
        this.nonBillable = false;
    }

    public Decimal amount() {
        return (quantity == null ? 0 : quantity) * (unitRate == null ? 0 : unitRate);
    }
}
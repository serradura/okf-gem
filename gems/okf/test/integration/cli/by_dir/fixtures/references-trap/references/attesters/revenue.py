def attest(receipt):
    return receipt.get("row_count", 0) > 0

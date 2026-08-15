"""Deterministic verdict for the revenue receipt: no model, no network."""


def attest(receipt):
    return receipt["row_count"] > 0 and receipt["bytes_billed"] < 10**10

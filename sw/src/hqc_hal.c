#include "hqc_hal.h"

/* core memory-mapped base register handle */
static HQC_Peripheral_t *HQC = NULL;

void hqc_dev_init(uintptr_t base_addr) {
    HQC = (HQC_Peripheral_t *)base_addr;
}

void hqc_dev_write_dense(hqc_bank_t bank, uint16_t word_idx, uint64_t val) {
    if (!HQC) return;

    HQC->MAR = ((uint32_t)word_idx << HQC_MAR_ADDR_POS) | (bank & HQC_MAR_BANK_MSK);
    HQC->MDR_L = (uint32_t)(val & 0xFFFFFFFFULL);
    
    /* write to MDR_H asserts core_we_pulse, committing 64 bits to BRAM atomically */
    HQC->MDR_H = (uint32_t)(val >> 32);
}

uint64_t hqc_dev_read_dense(hqc_bank_t bank, uint16_t word_idx) {
    if (!HQC) return 0ULL;

    HQC->MAR = ((uint32_t)word_idx << HQC_MAR_ADDR_POS) | (bank & HQC_MAR_BANK_MSK);
    uint32_t lo = HQC->MRR_L;
    uint32_t hi = HQC->MRR_H;
    return ((uint64_t)hi << 32) | (uint64_t)lo;
}

void hqc_dev_write_sparse(hqc_bank_t bank, uint16_t slot_idx, uint16_t pos) {
    if (!HQC) return;

    HQC->MAR = ((uint32_t)slot_idx << HQC_MAR_ADDR_POS) | (bank & HQC_MAR_BANK_MSK);
    HQC->MDR_L = (uint32_t)pos;
    HQC->MDR_H = 0; /* commit pulse */
}

uint16_t hqc_dev_read_sparse(hqc_bank_t bank, uint16_t slot_idx) {
    if (!HQC) return 0;

    HQC->MAR = ((uint32_t)slot_idx << HQC_MAR_ADDR_POS) | (bank & HQC_MAR_BANK_MSK);
    return (uint16_t)(HQC->MRR_L & 0x7FFF); /* N=17669 fits within 15-bit mask */
}

void hqc_dev_load_seed(const uint8_t seed[HQC_SEED_BYTES]) {
    if (!HQC || !seed) return;

    /* explicit little-endian unpacking avoids host endianness pitfalls */
    for (int i = 0; i < 4; i++) {
        const uint8_t *p = &seed[i * 4];
        HQC->PINR[i] = (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                       ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    }
}

void hqc_dev_read_seed(uint8_t seed[HQC_SEED_BYTES]) {
    if (!HQC || !seed) return;

    for (int i = 0; i < 4; i++) {
        uint32_t w = HQC->POUTR[i];
        seed[i * 4 + 0] = (uint8_t)(w);
        seed[i * 4 + 1] = (uint8_t)(w >> 8);
        seed[i * 4 + 2] = (uint8_t)(w >> 16);
        seed[i * 4 + 3] = (uint8_t)(w >> 24);
    }
}

hqc_status_t hqc_dev_exec(hqc_op_t op, uint32_t timeout_cycles) {
    if (!HQC) return HQC_STATUS_ERR_PARAM;

    /* START bit auto-clears on next clock in AXI wrapper */
    HQC->CR = ((uint32_t)(op & 0x3) << HQC_CR_OPCODE_POS) | HQC_CR_START;

    while ((HQC->SR & HQC_SR_DONE) == 0) {
        if (timeout_cycles && --timeout_cycles == 0) {
            return HQC_STATUS_ERR_TIMEOUT;
        }
    }

    if (op == HQC_OP_DECAP && !(HQC->SR & HQC_SR_VALID)) {
        return HQC_STATUS_ERR_ECC;
    }

    return HQC_STATUS_OK;
}

hqc_status_t hqc_accel_keygen(uint64_t pk_s[HQC_DENSE_WORDS],
                              const uint64_t pk_h[HQC_DENSE_WORDS],
                              const uint64_t sk_x[HQC_DENSE_WORDS],
                              const uint16_t sk_y[HQC_WEIGHT_Y]) {
    if (!pk_s || !pk_h || !sk_x || !sk_y) return HQC_STATUS_ERR_PARAM;

    /* stage generator h and secret noise x (dense, 277 words) */
    for (uint16_t i = 0; i < HQC_DENSE_WORDS; i++) {
        hqc_dev_write_dense(HQC_BANK_H, i, pk_h[i]);
        hqc_dev_write_dense(HQC_BANK_X, i, sk_x[i]);
    }

    /* stage sparse secret key indices (weight=66) */
    for (uint16_t i = 0; i < HQC_WEIGHT_Y; i++) {
        hqc_dev_write_sparse(HQC_BANK_Y, i, sk_y[i]);
    }

    hqc_status_t status = hqc_dev_exec(HQC_OP_KEYGEN, HQC_WATCHDOG_LIMIT);
    if (status != HQC_STATUS_OK) return status;

    for (uint16_t i = 0; i < HQC_DENSE_WORDS; i++) {
        pk_s[i] = hqc_dev_read_dense(HQC_BANK_S, i);
    }
    return HQC_STATUS_OK;
}

hqc_status_t hqc_accel_encap(uint64_t ct_u[HQC_DENSE_WORDS],
                             uint64_t ct_v[HQC_DENSE_WORDS],
                             const uint8_t seed_16B[HQC_SEED_BYTES],
                             const uint64_t pk_h[HQC_DENSE_WORDS],
                             const uint64_t pk_s[HQC_DENSE_WORDS],
                             const uint16_t r1[HQC_WEIGHT_R1],
                             const uint16_t r2[HQC_WEIGHT_R2],
                             const uint16_t e[HQC_WEIGHT_E]) {
    if (!ct_u || !ct_v || !seed_16B || !pk_h || !pk_s || !r1 || !r2 || !e) {
        return HQC_STATUS_ERR_PARAM;
    }

    hqc_dev_load_seed(seed_16B);

    for (uint16_t i = 0; i < HQC_DENSE_WORDS; i++) {
        hqc_dev_write_dense(HQC_BANK_H, i, pk_h[i]);
        hqc_dev_write_dense(HQC_BANK_S, i, pk_s[i]);
    }

    for (uint16_t i = 0; i < HQC_WEIGHT_R1; i++) hqc_dev_write_sparse(HQC_BANK_R1, i, r1[i]);
    for (uint16_t i = 0; i < HQC_WEIGHT_R2; i++) hqc_dev_write_sparse(HQC_BANK_R2, i, r2[i]);
    for (uint16_t i = 0; i < HQC_WEIGHT_E;  i++) hqc_dev_write_sparse(HQC_BANK_E,  i, e[i]);

    hqc_status_t status = hqc_dev_exec(HQC_OP_ENCAP, HQC_WATCHDOG_LIMIT);
    if (status != HQC_STATUS_OK) return status;

    for (uint16_t i = 0; i < HQC_DENSE_WORDS; i++) {
        ct_u[i] = hqc_dev_read_dense(HQC_BANK_U, i);
        ct_v[i] = hqc_dev_read_dense(HQC_BANK_V, i);
    }
    return HQC_STATUS_OK;
}

hqc_status_t hqc_accel_decap(uint8_t recovered_seed_16B[HQC_SEED_BYTES],
                             const uint64_t ct_u[HQC_DENSE_WORDS],
                             const uint64_t ct_v[HQC_DENSE_WORDS],
                             const uint16_t sk_y[HQC_WEIGHT_Y]) {
    if (!recovered_seed_16B || !ct_u || !ct_v || !sk_y) return HQC_STATUS_ERR_PARAM;

    for (uint16_t i = 0; i < HQC_DENSE_WORDS; i++) {
        hqc_dev_write_dense(HQC_BANK_U, i, ct_u[i]);
        hqc_dev_write_dense(HQC_BANK_V, i, ct_v[i]);
    }

    for (uint16_t i = 0; i < HQC_WEIGHT_Y; i++) {
        hqc_dev_write_sparse(HQC_BANK_Y, i, sk_y[i]);
    }

    hqc_status_t status = hqc_dev_exec(HQC_OP_DECAP, HQC_WATCHDOG_LIMIT);
    if (status != HQC_STATUS_OK) return status;

    hqc_dev_read_seed(recovered_seed_16B);
    return HQC_STATUS_OK;
}

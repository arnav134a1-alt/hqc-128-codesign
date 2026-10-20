#ifndef HQC_HAL_H
#define HQC_HAL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* HQC-128 ring parameters */
#define HQC_SECURITY_LEVEL      128
#define HQC_RING_N              17669
#define HQC_DATAPATH_WIDTH         64
#define HQC_DENSE_WORDS           277   /* ceil(17669 / 64) */

/* sparse vector weights */
#define HQC_WEIGHT_Y               66
#define HQC_WEIGHT_R1              66
#define HQC_WEIGHT_R2              66
#define HQC_WEIGHT_E               75

#define HQC_SEED_BYTES             16
#define HQC_WATCHDOG_LIMIT    5000000

/* register interface */
typedef struct {
    volatile uint32_t CR;
    volatile uint32_t SR;
    volatile uint32_t MAR;
    volatile uint32_t MDR_L;
    volatile uint32_t MDR_H;
    volatile uint32_t MRR_L;
    volatile uint32_t MRR_H;
    volatile uint32_t RESERVED;
    volatile uint32_t PINR[4];
    volatile uint32_t POUTR[4];
} HQC_Peripheral_t;

/* register bitfields */
#define HQC_CR_START            (1U << 0)
#define HQC_CR_OPCODE_POS       1
#define HQC_CR_OPCODE_MSK       (3U << HQC_CR_OPCODE_POS)
#define HQC_CR_SOFTRST          (1U << 3)

#define HQC_SR_BUSY             (1U << 0)
#define HQC_SR_DONE             (1U << 1)
#define HQC_SR_VALID            (1U << 2)

#define HQC_MAR_BANK_POS        0
#define HQC_MAR_BANK_MSK        (0x0FU << HQC_MAR_BANK_POS)
#define HQC_MAR_ADDR_POS        4
#define HQC_MAR_ADDR_MSK        (0x1FFU << HQC_MAR_ADDR_POS)

/* memory bank routing */
typedef enum {
    HQC_BANK_H   = 0x0,
    HQC_BANK_S   = 0x1,
    HQC_BANK_MG  = 0x2,
    HQC_BANK_U   = 0x3,
    HQC_BANK_V   = 0x4,
    HQC_BANK_R1  = 0x5,
    HQC_BANK_R2  = 0x6,
    HQC_BANK_E   = 0x7,
    HQC_BANK_Y   = 0x8,
    HQC_BANK_N   = 0x9,
    HQC_BANK_X   = 0xA
} hqc_bank_t;

/* opcodes */
typedef enum {
    HQC_OP_KEYGEN = 0x0,
    HQC_OP_ENCAP  = 0x1,
    HQC_OP_DECAP  = 0x2
} hqc_op_t;

/* error codes */
typedef enum {
    HQC_STATUS_OK          =  0,
    HQC_STATUS_ERR_TIMEOUT = -1,
    HQC_STATUS_ERR_PARAM   = -2,
    HQC_STATUS_ERR_ECC     = -3
} hqc_status_t;

/* hardware access */
void         hqc_dev_init(uintptr_t base_addr);
void         hqc_dev_write_dense(hqc_bank_t bank, uint16_t word_idx, uint64_t val);
uint64_t     hqc_dev_read_dense(hqc_bank_t bank, uint16_t word_idx);
void         hqc_dev_write_sparse(hqc_bank_t bank, uint16_t slot_idx, uint16_t pos);
uint16_t     hqc_dev_read_sparse(hqc_bank_t bank, uint16_t slot_idx);
void         hqc_dev_load_seed(const uint8_t seed[HQC_SEED_BYTES]);
void         hqc_dev_read_seed(uint8_t seed[HQC_SEED_BYTES]);
hqc_status_t hqc_dev_exec(hqc_op_t op, uint32_t timeout_cycles);

/* protocol routines */
hqc_status_t hqc_accel_keygen(uint64_t pk_s[HQC_DENSE_WORDS],
                              const uint64_t pk_h[HQC_DENSE_WORDS],
                              const uint64_t sk_x[HQC_DENSE_WORDS],
                              const uint16_t sk_y[HQC_WEIGHT_Y]);

hqc_status_t hqc_accel_encap(uint64_t ct_u[HQC_DENSE_WORDS],
                             uint64_t ct_v[HQC_DENSE_WORDS],
                             const uint8_t seed_16B[HQC_SEED_BYTES],
                             const uint64_t pk_h[HQC_DENSE_WORDS],
                             const uint64_t pk_s[HQC_DENSE_WORDS],
                             const uint16_t r1[HQC_WEIGHT_R1],
                             const uint16_t r2[HQC_WEIGHT_R2],
                             const uint16_t e[HQC_WEIGHT_E]);

hqc_status_t hqc_accel_decap(uint8_t recovered_seed_16B[HQC_SEED_BYTES],
                             const uint64_t ct_u[HQC_DENSE_WORDS],
                             const uint64_t ct_v[HQC_DENSE_WORDS],
                             const uint16_t sk_y[HQC_WEIGHT_Y]);

#ifdef __cplusplus
}
#endif

#endif /* HQC_HAL_H */

// Copyright 2026 CheshireAra contributors.
// SPDX-License-Identifier: Apache-2.0
// Host-only address controls for the real PLIC DIF compiled with MOCK_MMIO.
// The expected addresses come from generated register macros, not DIF helpers.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "rv_plic_regs.h"
#include "sw/device/lib/dif/dif_rv_plic.h"

#ifdef OT_PLATFORM_RV32
#error "Host control must use the instrumented MMIO interface"
#endif

_Static_assert(RV_PLIC_PARAM_NUM_TARGET <= 2, "Test supports one or two targets");
_Static_assert(RV_PLIC_IE0_MULTIREG_COUNT <= 2, "Test supports up to 64 sources");

struct operation { bool write; ptrdiff_t offset; uint32_t value; };
static struct operation operations[128];
static unsigned expected_count, actual_count, failures, cases;
static const char *case_name;
static unsigned char identity;

static void expect(bool write, ptrdiff_t offset, uint32_t value) {
    if (expected_count >= sizeof(operations) / sizeof(operations[0])) {
        fprintf(stderr, "FAIL: expectation capacity\n");
        ++failures;
        return;
    }
    operations[expected_count++] = (struct operation){write, offset, value};
}
static void begin(const char *name) {
    case_name = name;
    expected_count = actual_count = 0;
    ++cases;
}
static void finish(dif_result_t got, dif_result_t want) {
    if (got != want || actual_count != expected_count) {
        fprintf(stderr, "FAIL %s: result=%u/%u operations=%u/%u\n", case_name,
                (unsigned)got, (unsigned)want, actual_count, expected_count);
        ++failures;
    }
}
static uint32_t observe(mmio_region_t base, bool write, ptrdiff_t offset,
                        uint32_t value) {
    unsigned index = actual_count++;
    if (index >= expected_count) {
        fprintf(stderr, "FAIL %s: unexpected %s offset=%#tx\n", case_name,
                write ? "write" : "read", offset);
        ++failures;
        return 0;
    }
    struct operation wanted = operations[index];
    if (base.mock != &identity || write != wanted.write || offset != wanted.offset ||
        (write && value != wanted.value)) {
        fprintf(stderr, "FAIL %s op%u: %c offset=%#tx value=%#x; wanted %c offset=%#tx value=%#x\n",
                case_name, index, write ? 'W' : 'R', offset, value,
                wanted.write ? 'W' : 'R', wanted.offset, wanted.value);
        ++failures;
    }
    return wanted.value;
}

uint32_t mmio_region_read32(mmio_region_t base, ptrdiff_t offset) {
    return observe(base, false, offset, 0);
}
void mmio_region_write32(mmio_region_t base, ptrdiff_t offset, uint32_t value) {
    (void)observe(base, true, offset, value);
}

int main(void) {
    const dif_rv_plic_t plic = {.base_addr = {.mock = &identity}};
#if RV_PLIC_IE0_MULTIREG_COUNT == 1
    const ptrdiff_t ie[RV_PLIC_PARAM_NUM_TARGET][1] = {
        {RV_PLIC_IE0_REG_OFFSET},
#if RV_PLIC_PARAM_NUM_TARGET > 1
        {RV_PLIC_IE1_REG_OFFSET},
#endif
    };
#else
    const ptrdiff_t ie[RV_PLIC_PARAM_NUM_TARGET][2] = {
        {RV_PLIC_IE0_0_REG_OFFSET, RV_PLIC_IE0_1_REG_OFFSET},
#if RV_PLIC_PARAM_NUM_TARGET > 1
        {RV_PLIC_IE1_0_REG_OFFSET, RV_PLIC_IE1_1_REG_OFFSET},
#endif
    };
#endif
    const ptrdiff_t threshold[RV_PLIC_PARAM_NUM_TARGET] = {
        RV_PLIC_THRESHOLD0_REG_OFFSET,
#if RV_PLIC_PARAM_NUM_TARGET > 1
        RV_PLIC_THRESHOLD1_REG_OFFSET,
#endif
    };
    const ptrdiff_t cc[RV_PLIC_PARAM_NUM_TARGET] = {
        RV_PLIC_CC0_REG_OFFSET,
#if RV_PLIC_PARAM_NUM_TARGET > 1
        RV_PLIC_CC1_REG_OFFSET,
#endif
    };
    for (uint32_t target = 0; target < RV_PLIC_PARAM_NUM_TARGET; ++target) {
        for (uint32_t irq = 0; irq < RV_PLIC_PARAM_NUM_SRC; ++irq) {
            uint32_t bit = UINT32_C(1) << (irq % 32);
            ptrdiff_t offset = ie[target][irq / 32];
            dif_toggle_t state = kDifToggleDisabled;
            begin(target ? "S get-enabled" : "M get-enabled");
            expect(false, offset, bit);
            finish(dif_rv_plic_irq_get_enabled(&plic, irq, target, &state), kDifOk);
            if (state != kDifToggleEnabled) ++failures;
            begin(target ? "S enable" : "M enable");
            expect(false, offset, ~bit); expect(true, offset, UINT32_MAX);
            finish(dif_rv_plic_irq_set_enabled(&plic, irq, target, kDifToggleEnabled), kDifOk);
            begin(target ? "S disable" : "M disable");
            expect(false, offset, UINT32_MAX); expect(true, offset, ~bit);
            finish(dif_rv_plic_irq_set_enabled(&plic, irq, target, kDifToggleDisabled), kDifOk);
        }
        for (uint32_t priority = 0; priority <= 7; ++priority) {
            begin(target ? "S threshold" : "M threshold");
            expect(true, threshold[target], priority);
            finish(dif_rv_plic_target_set_threshold(&plic, target, priority), kDifOk);
        }
        for (uint32_t irq = 0; irq < RV_PLIC_PARAM_NUM_SRC; ++irq) {
            uint32_t claim = UINT32_MAX;
            begin(target ? "S claim" : "M claim");
            expect(false, cc[target], irq);
            finish(dif_rv_plic_irq_claim(&plic, target, &claim), kDifOk);
            if (claim != irq) ++failures;
            begin(target ? "S complete" : "M complete");
            expect(true, cc[target], irq);
            finish(dif_rv_plic_irq_complete(&plic, target, irq), kDifOk);
        }
    }
    begin("invalid enable target: no MMIO");
    finish(dif_rv_plic_irq_set_enabled(&plic, 20, RV_PLIC_PARAM_NUM_TARGET, kDifToggleEnabled), kDifBadArg);
    begin("invalid threshold target: no MMIO");
    finish(dif_rv_plic_target_set_threshold(&plic, RV_PLIC_PARAM_NUM_TARGET, 1), kDifBadArg);
    begin("invalid claim target: no MMIO");
    uint32_t claim;
    finish(dif_rv_plic_irq_claim(&plic, RV_PLIC_PARAM_NUM_TARGET, &claim), kDifBadArg);
    begin("invalid complete target: no MMIO");
    finish(dif_rv_plic_irq_complete(&plic, RV_PLIC_PARAM_NUM_TARGET, 20), kDifBadArg);
    begin("invalid IRQ: no MMIO");
    finish(dif_rv_plic_irq_set_enabled(&plic, RV_PLIC_PARAM_NUM_SRC, 0, kDifToggleEnabled), kDifBadArg);
    begin("invalid threshold: no MMIO");
    finish(dif_rv_plic_target_set_threshold(&plic, 0, 8), kDifBadArg);
    begin("null claim output: no MMIO");
    finish(dif_rv_plic_irq_claim(&plic, 0, NULL), kDifBadArg);
    printf("MOCK_MMIO_PLIC_ADDRESS cases=%u errors=%u\n", cases, failures);
    return failures ? 1 : 0;
}

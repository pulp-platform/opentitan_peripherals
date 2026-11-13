# PLIC DIF target addresses

The generated PLIC maps interrupt enables at 0x80-byte target intervals.
Threshold and claim/complete registers use 0x1000-byte target intervals.
The DIF previously used packed word intervals for all three groups.
Target 1 therefore accessed target 0 registers or reserved addresses.

The patch calculates each interval from generated target 0 and target 1 offsets.
It preserves the single-target configuration and both single-register and multireg IE layouts.
It does not change hardware, register generation, MSIP, or the public DIF API.
The vendor patch preserves this change when the pinned lowRISC source is imported again.
Both vendor patches reproduced the exact candidate from lowRISC `9f497f6339b4484fc5b7e5dc5d4bc63f55ec3c35`.

The host test compiles the actual DIF with its existing `MOCK_MMIO` interface.
The expected addresses come directly from the generated register macros.
It checks get/enable/disable for every source, threshold 0 through 7,
claim/complete IDs, and invalid arguments with no MMIO.

Official base: `cd3153de2783abd3d03d0595e6c4b32413c62f14`.
Register generation used its unmodified templates and register_interface tool revision
`ae616e5a1ec2b41e72d200e5ab09c65e94aebd3d`.
GCC compiled all eight host runs with `-Wall -Wextra -Werror`.

| Sources | Targets | Cases | Original errors | Patched errors |
| --- | --- | --- | --- | --- |
| 32 | 1 | 175 | 0 | 0 |
| 58 | 1 | 305 | 0 | 0 |
| 32 | 2 | 343 | 232 | 0 |
| 58 | 2 | 603 | 414 | 0 |

## Reproduction

Use the official `util/ipgen.py` and the register_interface `regtool.py`.
Set `REGUTIL` to the directory containing `regtool.py`.
For each configuration, create a distinct output directory and config file.
For example, from this repository root:

```bash
mkdir test-plic-58-2
printf '%s\n' '{instance_name: "rv_plic", param_values: {src: 58, target: 2, prio: 7}}' \
  > test-plic-58-2/config.hjson
PYTHONPATH="$REGUTIL" python3 util/ipgen.py generate \
  -C src/rv_plic/tpl/rv_plic -o test-plic-58-2/generated \
  -c test-plic-58-2/config.hjson
python3 "$REGUTIL/regtool.py" --cdefines test-plic-58-2/generated/data/rv_plic.hjson \
  > test-plic-58-2/rv_plic_regs.h
gcc -std=c11 -Wall -Wextra -Werror -DMOCK_MMIO -I. -Itest-plic-58-2 \
  sw/device/lib/dif/dif_rv_plic.c sw/device/lib/base/bitfield.c \
  sw/tests/dif_rv_plic_target_addresses.c -o test-plic-58-2/test
./test-plic-58-2/test
```

Repeat with 32/1, 58/1, and 32/2. For the original comparison, compile the same
input and generated header with only `dif_rv_plic.c` restored from the stated base.
This is a software address test. It does not simulate PLIC arbitration or hardware MMIO side effects.

AI assistance: OpenAI Codex assisted implementation, test adaptation, and validation.

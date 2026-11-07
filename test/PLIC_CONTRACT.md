# Live eligible PLIC claims

The CC read path previously used the registered interrupt-notification ID.
Adjacent accepted claims could therefore return and consume the same pending source twice.
The raw max-tree output also allowed a priority-zero source to be claimed.

Use a separate live claim ID from the current pending/enabled set.
Exclude priority zero. Preserve the registered notification and its ID.
Threshold continues to gate notification only.
This follows the [PLIC 1.0.0 claim and priority rules](https://github.com/riscv/riscv-plic-spec/blob/f8ec1b7e9b1a92c34af8e0ab7eb33838813785a3/riscv-plic.adoc).
The [priority-zero clarification](https://github.com/riscv/riscv-plic-spec/issues/26#issuecomment-1086882033)
also applies.

| Profile | Checks | Original errors | Patched errors |
| --- | --- | --- | --- |
| back_to_back_claim | 581 | 2 | 0 |
| priority_zero | 680 | 80 | 0 |
| claim_regression | 20457356 | Not run | 0 |

The regression exercised 215584 vectors and finished at 13.740830 ms.
It includes every source and priority, threshold boundaries, equal-priority ID
selection, independent contexts, adjacent claims, and resets.
It does not include the separate disabled-completion fix.

## Official inputs

Base: `pulp-platform/opentitan_peripherals@cd3153de2783abd3d03d0595e6c4b32413c62f14`.
The independent candidates each start from that base.
The test uses the official generated 58-source, two-target PLIC with three priority bits.
The checked-in default RTL also comes from the modified official templates.
The vendor patch preserves the template change on re-import.
The complete patch series reproduced the exact templates from pinned lowRISC
`9f497f6339b4484fc5b7e5dc5d4bc63f55ec3c35`.

Dependencies: common_cells `1.39.0@9ca8a7655f741e7dd5736669a20a301325194c28`
and register_interface `v0.3.9`.
The test uses the real register interface, synchronizers, gateway, max tree,
register block, and target modules. Its reference uses bus transactions and
source levels. It does not use the DUT winner as its expected result.

## Reproduction

Set `CELLS` and `REGIF` to those dependency checkouts.
Set `REGUTIL=$REGIF/vendor/lowrisc_opentitan/util`.
From the repository root with VCS on PATH, use a new output directory:

```bash
ROOT=$PWD
mkdir test-plic-contract
cd test-plic-contract
cat > config.hjson <<'JSON'
{instance_name: "rv_plic", param_values: {src: 58, target: 2, prio: 7}}
JSON
PYTHONPATH="$REGUTIL" python3 "$ROOT/util/ipgen.py" generate \
  -C "$ROOT/src/rv_plic/tpl/rv_plic" -o generated -c config.hjson
DEPS=("$CELLS/src/sync.sv" "$REGIF/src/reg_intf.sv")
for module in prim_subreg_arb prim_subreg prim_subreg_ext; do
  DEPS+=("$REGIF/vendor/lowrisc_opentitan/src/$module.sv")
done
DEPS+=("$ROOT/src/prim/prim_pulp_platform/prim_flop_2sync.sv")
DEPS+=("$ROOT/src/prim/rtl/prim_max_tree.sv")
for module in rv_plic_reg_pkg rv_plic_gateway rv_plic_target rv_plic_reg_top rv_plic; do
  DEPS+=("$PWD/generated/rtl/$module.sv")
done
timeout 180 vcs -full64 -sverilog -timescale=1ns/1ps +lint=all \
  "+incdir+$CELLS/include" "+incdir+$REGIF/include" "${DEPS[@]}" \
  "$ROOT/test/tb_plic_contract.sv" -top tb_e_plic_unit -o simv -l compile.log
```

Run the listed profiles in distinct subdirectories:

```bash
for profile in back_to_back_claim priority_zero claim_regression; do
  mkdir "$profile"
  (cd "$profile"; timeout 90 ../simv "+E_PLIC_PROFILE=$profile" -l run.log)
done
```

For the original comparison, use an unchanged checkout of the stated base,
the same test source and dependencies, and a separate generated/output directory.
Every run must produce exactly one `E_PLIC_DONE` with the listed counts.
Candidate runs must have zero errors, no assertion failures, and normal `$finish`.
The originals must produce the specified errors and the functional-failure marker.
Do not classify by process exit code: VCS can return zero after `$fatal`.
The test includes a 50 ms HDL deadline. Each run also has a 90-second wall-clock limit.

## Implementation checks and scope

VCS W-2024.09-SP1 compiled and elaborated the original and both candidates with lint.
The final candidates add no lint categories to the baseline.
Inherited lint categories include NS, UII-L, SVA-CE, SVA-DIU, WMIA-L, and CAWM-L.
Design Compiler W-2024.09-SP1 checked the complete 58-source/two-target PLIC
through a wrapper exposing all data and control ports. GTECH `compile -no_map`
reported 896 flip-flops and zero latches, combinational loops, multiple-driver
nets, unexplained references, or post-compile blackboxes for each version.
Existing generic-netlist writer and unconstrained-endpoint warnings remain.
An extra VO-11 writer warning names unused nets after optimization.
These checks do not claim technology mapping, timing closure, or physical signoff.

This is real PLIC module validation. It does not simulate the whole SoC.
The independent completion and claim fixes have separate results and branches.
AI assistance: OpenAI Codex assisted implementation, tests, and validation.

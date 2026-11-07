# Standard SPI transmit-enable lifetime

This change adapts the held-final-bit method from Harry Callahan's merged
[lowRISC PR #22040](https://github.com/lowRISC/opentitan/pull/22040), commit
`e3ca274e77a7f2bf22f6d460f7e14734f32f1570`.
The current PULP snapshot predates that change.

The older PULP FSM also needs boundaries for the held bit: clear on software
reset or idle CS, clear a completed byte before setting a new hold, retain the
hold under stall, and set it only in an active clock state. A direct adaptation
of the upstream hold can otherwise drive MOSI in a following RX segment.
The original authors and Apache-2.0 license remain unchanged.

The intended standard-mode behavior drives MOSI during TX samples and disables
it during RX samples. This is the selected implementation contract, not a
universal SPI electrical rule. A retained-CS gap with a still-latched TX command
is not an RX segment; the test does not require its MOSI enable to be zero.

## Fixed inputs and results

PULP opentitan_peripherals master `cd3153de2783abd3d03d0595e6c4b32413c62f14`.
Dependencies satisfy the official declarations: common_cells 1.39.0
`9ca8a7655f741e7dd5736669a20a301325194c28`, tech_cells_generic 0.2.13
`7968dd6e6180df2c644636bc6d2908a49f2190cf`, register_interface 0.3.9
`146501d80052b61475cdc333d3aab4cd769fd5dc`.
No dependency, register layout, hardware parameter or public interface changes.

The actual complete `spi_host` executes the same public register transactions
and independent pin endpoint in all three versions. No DUT state is forced.
The test uses known TX/RX byte patterns, all four modes and three CS outputs.
It checks actual MOSI payload and enable, MISO receive data, FIFO starvation/full
stall recovery, events, errors, continuous-CS TX/RX handoff and software reset
in a final TX bit followed by RX. Sampling observes settled outputs 1 ps after
the SCK event. No EEPROM or NOR model is needed.

| Profile | Cases | Checks | Original errors | Author-only errors | This change errors |
| --- | ---: | ---: | ---: | ---: | ---: |
| mode | 60 | 4940 | 0 | 32 | 0 |
| fifo | 2 | 2378 | 0 | 8 | 0 |
| event | 12 | 6690 | 0 | 26 | 0 |
| error | 16 | 1424 | 0 | 0 | 0 |
| handoff | 8 | 212 | 2 | 48 | 0 |
| reset_hold | 4 | 120 | 0 | 32 | 0 |

All 18 VCS W-2024.09-SP1 runs reach the single DONE. Nonzero original/author
error totals trigger the expected TB fatal. All six final-candidate profiles
finish normally within the finite HDL and wall limits.
The final candidate has 102 cases / 15764 checks / zero errors.
All three builds have zero VCS lint diagnostics. Functional assertions remain
enabled. Require zero test and assertion errors; simv process return alone is
not a pass. Each profile has a 5 ms HDL deadline and 60 s wall limit.
Unknown, missing or deadline output is a failure.

Three full real FSM DC generic `compile -no_map` checks at NumCS=3 found
104 flip-flops / 1406 cells originally and 105 / 1418 for both author and local
candidates. All have zero latches, combinational loops, multiple drivers,
unexplained cells or final blackboxes. These are structure checks with a 5 ns
reference clock, not technology timing or physical signoff.
`patches/spi_host/0003-*` replays byte-for-byte after the existing vendor patches
from their pinned lowRISC base `9f497f6339b4484fc5b7e5dc5d4bc63f55ec3c35`.
This does not claim current lowRISC main functional verification or whole-SoC
validation.

## Reproduction

Set `OT`, `CC`, `TC`, and `REG` to those fixed checkouts. Set `FSM` to the
candidate FSM file, the original from the stated base, or the author-only
adaptation. Keep the same test and all other inputs.
From a new output directory:

```bash
sources=("$TC/src/rtl/tc_clk.sv" "$CC/src/cf_math_pkg.sv"
         "$OT/src/prim/rtl/prim_util_pkg.sv"
         "$OT/src/spi_host/rtl/spi_host_reg_pkg.sv"
         "$OT/src/spi_host/rtl/spi_host_cmd_pkg.sv")
for cell in prim_subreg_arb prim_subreg_ext prim_subreg; do
  sources+=("$REG/vendor/lowrisc_opentitan/src/$cell.sv")
done
sources+=("$REG/src/reg_demux.sv" "$OT/src/prim/prim_pulp_platform/prim_flop_en.sv")
for cell in prim_fifo_sync_cnt prim_fifo_sync prim_packer_fifo prim_intr_hw; do
  sources+=("$OT/src/prim/rtl/$cell.sv")
done
for cell in spi_host_reg_top spi_host_byte_merge spi_host_byte_select \
            spi_host_command_queue spi_host_window spi_host_data_fifos \
            spi_host_shift_register; do
  sources+=("$OT/src/spi_host/rtl/$cell.sv")
done
timeout 180 vcs -full64 -sverilog -timescale=1ns/1ps +lint=all \
  "+incdir+$CC/include+$REG/include" "${sources[@]}" "$FSM" \
  "$OT/src/spi_host/rtl/spi_host_core.sv" "$OT/src/spi_host/rtl/spi_host.sv" \
  "$OT/test/tb_spi_tx_enable.sv" -top tb_spi_tx_enable -o simv -l compile.log
for profile in mode fifo event error handoff reset_hold; do
  mkdir "$profile"
  (cd "$profile"; timeout 60 ../simv "+E_SPI_PROFILE=$profile" -l run.log)
done
```

To reproduce the author-only comparison, start with the candidate source and
replace only the `cmd_wr_en_last_bit` always_ff block with the original author's
block below. Keep the OR in `sd_en_o[0]` and every other source unchanged.
The original comparison uses the base file, which has neither this block nor the OR.

```systemverilog
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cmd_wr_en_last_bit <= 1'b0;
    end else if (cmd_wr_en_q & last_bit) begin
      cmd_wr_en_last_bit <= 1'b1;
    end else if (byte_ending) begin
      cmd_wr_en_last_bit <= 1'b0;
    end else begin
      cmd_wr_en_last_bit <= cmd_wr_en_last_bit;
    end
  end
```

AI assistance: OpenAI Codex assisted implementation, test and validation.

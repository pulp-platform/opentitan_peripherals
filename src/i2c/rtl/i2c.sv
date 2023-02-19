// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Description: I2C top level wrapper file

`include "common_cells/assertions.svh"

module i2c
  import i2c_reg_pkg::*;
#(
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic
) (
  input                     clk_i,
  input                     rst_ni,

  // Bus Interface
  input  reg_req_t reg_req_i,
  output reg_rsp_t reg_rsp_o,

  // Generic IO
  input                     cio_scl_i,
  output logic              cio_scl_o,
  output logic              cio_scl_en_o,
  input                     cio_sda_i,
  output logic              cio_sda_o,
  output logic              cio_sda_en_o,

  // Interrupts
  output logic              intr_fmt_threshold_o,
  output logic              intr_rx_threshold_o,
  output logic              intr_fmt_overflow_o,
  output logic              intr_rx_overflow_o,
  output logic              intr_nak_o,
  output logic              intr_scl_interference_o,
  output logic              intr_sda_interference_o,
  output logic              intr_stretch_timeout_o,
  output logic              intr_sda_unstable_o,
  output logic              intr_cmd_complete_o,
  output logic              intr_tx_stretch_o,
  output logic              intr_tx_overflow_o,
  output logic              intr_acq_full_o,
  output logic              intr_unexp_stop_o,
  output logic              intr_host_timeout_o
);

  i2c_reg2hw_t reg2hw;
  i2c_hw2reg_t hw2reg;

  i2c_reg_top #(
    .reg_req_t (reg_req_t),
    .reg_rsp_t (reg_rsp_t)
  ) u_reg (
    .clk_i,
    .rst_ni,
    .reg_req_i,
    .reg_rsp_o,
    .reg2hw,
    .hw2reg,
    .devmode_i(1'b1)
  );

  logic scl_int;
  logic sda_int;

  i2c_core i2c_core (
    .clk_i,
    .rst_ni,
    .reg2hw,
    .hw2reg,

    .scl_i(cio_scl_i),
    .scl_o(scl_int),
    .sda_i(cio_sda_i),
    .sda_o(sda_int),

    .intr_fmt_threshold_o,
    .intr_rx_threshold_o,
    .intr_fmt_overflow_o,
    .intr_rx_overflow_o,
    .intr_nak_o,
    .intr_scl_interference_o,
    .intr_sda_interference_o,
    .intr_stretch_timeout_o,
    .intr_sda_unstable_o,
    .intr_cmd_complete_o,
    .intr_tx_stretch_o,
    .intr_tx_overflow_o,
    .intr_acq_full_o,
    .intr_unexp_stop_o,
    .intr_host_timeout_o
  );

  // For I2C, in standard, fast and fast-plus modes, outputs simulated as open-drain outputs.
  // Asserting scl or sda high should be equivalent to a tri-state output.
  // The output, when enabled, should only assert low.

  assign cio_scl_o = 1'b0;
  assign cio_sda_o = 1'b0;

  assign cio_scl_en_o = ~scl_int;
  assign cio_sda_en_o = ~sda_int;

  `ASSERT_KNOWN(CioSclKnownO_A, cio_scl_o)
  `ASSERT_KNOWN(CioSclEnKnownO_A, cio_scl_en_o)
  `ASSERT_KNOWN(CioSdaKnownO_A, cio_sda_o)
  `ASSERT_KNOWN(CioSdaEnKnownO_A, cio_sda_en_o)
  `ASSERT_KNOWN(IntrFmtWtmkKnownO_A, intr_fmt_threshold_o)
  `ASSERT_KNOWN(IntrRxWtmkKnownO_A, intr_rx_threshold_o)
  `ASSERT_KNOWN(IntrFmtOflwKnownO_A, intr_fmt_overflow_o)
  `ASSERT_KNOWN(IntrRxOflwKnownO_A, intr_rx_overflow_o)
  `ASSERT_KNOWN(IntrNakKnownO_A, intr_nak_o)
  `ASSERT_KNOWN(IntrSclInterfKnownO_A, intr_scl_interference_o)
  `ASSERT_KNOWN(IntrSdaInterfKnownO_A, intr_sda_interference_o)
  `ASSERT_KNOWN(IntrStretchTimeoutKnownO_A, intr_stretch_timeout_o)
  `ASSERT_KNOWN(IntrSdaUnstableKnownO_A, intr_sda_unstable_o)
  `ASSERT_KNOWN(IntrCommandCompleteKnownO_A, intr_cmd_complete_o)
  `ASSERT_KNOWN(IntrTxStretchKnownO_A, intr_tx_stretch_o)
  `ASSERT_KNOWN(IntrTxOflwKnownO_A, intr_tx_overflow_o)
  `ASSERT_KNOWN(IntrAcqFulllwKnownO_A, intr_acq_full_o)
  `ASSERT_KNOWN(IntrUnexpStopKnownO_A, intr_unexp_stop_o)
  `ASSERT_KNOWN(IntrHostTimeoutKnownO_A, intr_host_timeout_o)

endmodule

// Copyright 2021 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Double-synchronizer flop implementation for opentitan primitive cells
// using cells from pulp_platform common_cells.

// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "common_cells/assertions.svh"

module prim_flop_en #(
  parameter int               Width      = 1,
  parameter bit               EnSecBuf   = 0,
  parameter logic [Width-1:0] ResetValue = 0
) (
  input                    clk_i,
  input                    rst_ni,
  input                    en_i,
  input        [Width-1:0] d_i,
  output logic [Width-1:0] q_o
);

  logic en;
  if (EnSecBuf) begin : gen_en_sec_buf
    tc_clk_buffer u_en_buf (
      .clk_i ( en_i ),
      .clk_o ( en )
    );
  end else begin : gen_en_no_sec_buf
    assign en = en_i;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      q_o <= ResetValue;
    end else if (en) begin
      q_o <= d_i;
    end
  end

endmodule

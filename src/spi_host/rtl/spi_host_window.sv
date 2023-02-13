// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Module to manage TX FIFO window for Serial Peripheral Interface (SPI) host IP.
//

`include "common_cells/assertions.svh"

module spi_host_window #(
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic
)(
  input  clk_i,
  input  rst_ni,
  input  reg_req_t          rx_win_i,
  output reg_rsp_t          rx_win_o,
  input  reg_req_t          tx_win_i,
  output reg_rsp_t          tx_win_o,
  output logic [31:0]       tx_data_o,
  output logic [3:0]        tx_be_o,
  output logic              tx_valid_o,
  input        [31:0]       rx_data_i,
  output logic              rx_ready_o
);

  localparam int AW = spi_host_reg_pkg::BlockAw;
  localparam int DW = 32;
  localparam int ByteMaskW = DW / 8;

  logic         rx_we;

  // Only support reads from the data RX fifo window
  logic  rx_access_error;
  assign rx_access_error = rx_we;

  // Check that our RX regbus data is 32 bit wide
  `ASSERT_INIT(RegbusIs32Bit, $bits(rx_win_i.wdata) == 32)

  // We are already a regbus, so no stateful adapter should be needed here
  // Request
  assign rx_we        = rx_win_i.valid & rx_win_i.write;    // write-enable
  assign rx_ready_o   = rx_win_i.valid & ~rx_win_i.write;   // read-enable
  // Response: always ready, else over/underflow error reported in regfile
  assign rx_win_o.rdata  = rx_data_i;
  assign rx_win_o.error  = rx_access_error;
  assign rx_win_o.ready  = 1'b1;

  // Check that our TX regbus data is 32 bit wide
  `ASSERT_INIT(RegbusIs32Bit, $bits(tx_win_i.wdata) == 32)

  // We are already a regbus, so no stateful adapter should be needed here
  // Request
  assign tx_valid_o   = tx_win_i.valid;
  assign tx_data_o    = tx_win_i.wdata;
  assign tx_be_o      = tx_win_i.wstrb;
  // Response: always grant and no error, else over/underflow error reported in regfile
  assign tx_win_o.error  = 1'b0;
  assign tx_win_o.ready  = 1'b1;

endmodule : spi_host_window

// Copyright 2026 CheshireAra contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
// Test-only standard-SPI endpoint and register-interface driver.
// DUT: PULP opentitan_peripherals cd3153de2783abd3d03d0595e6c4b32413c62f14.
// The endpoint uses public pins. It neither forces DUT state nor copies a DUT
// data FIFO to obtain expected data. Profiles are finite; the outer runner owns
// the HDL and wall limits for an absent positive event.
`timescale 1ns/1ps
module tb_spi_tx_enable;
  typedef struct packed {logic valid,write;logic[47:0]addr;logic[31:0]wdata;logic[3:0]wstrb;} reg_req_t;
  typedef struct packed {logic ready,error;logic[31:0]rdata;} reg_rsp_t;
  logic clk=0,rst_n=0;
  always #2.5ns clk=~clk;
  reg_req_t req='0;
  reg_rsp_t rsp;
  logic sck,sck_en;
  logic [2:0] csb,csb_en;
  logic [3:0] sd_o,sd_en,sd_i=0;
  logic irq_error,irq_event;
  spi_host #(.reg_req_t(reg_req_t),.reg_rsp_t(reg_rsp_t)) dut(
    .clk_i(clk),.rst_ni(rst_n),.reg_req_i(req),.reg_rsp_o(rsp),
    .cio_sck_o(sck),.cio_sck_en_o(sck_en),.cio_csb_o(csb),.cio_csb_en_o(csb_en),
    .cio_sd_o(sd_o),.cio_sd_en_o(sd_en),.cio_sd_i(sd_i),
    .intr_error_o(irq_error),.intr_spi_event_o(irq_event));
  localparam int INTR_STATE='h00,INTR_ENABLE='h04,CONTROL='h10,STATUS='h14;
  localparam int CONFIG0='h18,CSID='h24,COMMAND='h28,RXDATA='h2c,TXDATA='h30;
  localparam int ERROR_ENABLE='h34,ERROR_STATUS='h38,EVENT_ENABLE='h3c;
  localparam logic [31:0] Enable=32'ha0000000;
  string profile="mode";
  int unsigned case_id=0,cases=0,checks=0,errors=0,mmio_count=0;
  int unsigned spi_mode=0,spi_div=1,selected_cs=0,direction=0,nbytes=0;
  int unsigned sampled_bits=0,edge_count=0,transfers=0;
  bit transfer_enabled=0;
  logic previous_sck=0;
  longint unsigned cycle=0;
  function automatic longint unsigned ps();return longint'($realtime/1ps);endfunction
  function automatic byte unsigned tx_pattern(input int unsigned i);
    return byte'('h3c+13*i+7*case_id);
  endfunction
  function automatic byte unsigned rx_pattern(input int unsigned i);
    return byte'('ha5+37*i+11*case_id);
  endfunction
  task automatic fail(input string reason);
    errors++;$error("[SPI_TX_ENABLE_ERROR] case=%0d cycle=%0d %s",case_id,cycle,reason);
  endtask
  task automatic check(input string name,input logic [31:0] actual,
                       input logic [31:0] gold,input logic [31:0] mask='1);
    checks++;
    $display("[SPI_TX_ENABLE_CHECK] case=%0d name=%s actual=%08h mask=%08h",case_id,name,actual,mask);
    if($isunknown(actual&mask))begin
      $display("[SPI_TX_ENABLE_UNKNOWN] case=%0d name=%s",case_id,name);wait(1'b0);
    end
    if((actual&mask)!=(gold&mask))fail($sformatf("%s actual=%08h expected=%08h mask=%08h",name,actual,gold,mask));
  endtask
  task automatic access(input bit write,input int unsigned addr,
                        input logic [31:0] data,input logic [3:0] be,
                        output logic [31:0] result);
    @(negedge clk);req='0;req.valid=1;req.write=write;req.addr=addr;req.wdata=data;req.wstrb=be;
    do @(posedge clk);while(rsp.ready!==1'b1);
    result=rsp.rdata;mmio_count++;
    $display("[SPI_TX_ENABLE_MMIO] case=%0d cycle=%0d time_ps=%0d addr=%012h write=%b wdata=%08h wstrb=%h rdata=%08h error=%b",
      case_id,cycle,ps(),req.addr,req.write,req.wdata,req.wstrb,rsp.rdata,rsp.error);
    if(rsp.error!==1'b0)fail("unexpected register-interface error");
    @(negedge clk);req='0;
  endtask
  task automatic wr(input int unsigned a,input logic [31:0] d,input logic [3:0] be=4'hf);
    logic [31:0] unused;access(1,a,d,be,unused);
  endtask
  task automatic rd(input int unsigned a,output logic [31:0] d);access(0,a,0,0,d);endtask
  task automatic status_wait(input logic [31:0] mask,input logic [31:0] value);
    logic [31:0] s;
    do rd(STATUS,s);while((s&mask)!==value);
  endtask
  task automatic reset_core;
    logic [31:0] s;
    transfer_enabled=0;
    wr(CONTROL,32'h40000000);repeat(12)@(posedge clk);
    status_wait(32'h4000ffff,0);
    wr(CONTROL,0);wr(ERROR_STATUS,'h3f);wr(INTR_STATE,3);
    wr(INTR_ENABLE,0);wr(EVENT_ENABLE,0);wr(ERROR_ENABLE,'h1f);
    repeat(12)@(posedge clk);
  endtask
  task automatic configure(input int unsigned mode_value,input int unsigned div_value,
                            input int unsigned cs_value,input logic [31:0] extra_control=0);
    logic [31:0] config_value;
    spi_mode=mode_value;spi_div=div_value;selected_cs=cs_value;
    config_value=(32'(mode_value>>1)<<31)|(32'(mode_value&1)<<30)|32'h02220000|div_value;
    for(int i=0;i<3;i++)wr(CONFIG0+4*i,config_value);
    wr(CSID,cs_value);wr(CONTROL,extra_control);
  endtask
  task automatic begin_case(input string kind,input int unsigned ordinal,
                            input int unsigned variant=0,input int unsigned mask_value=0);
    case_id=ordinal;cases++;
    $display("[SPI_TX_ENABLE_CASE] id=%0d profile=%s kind=%s variant=%0d mask=%0d",case_id,profile,kind,variant,mask_value);
    reset_core();
  endtask
  task automatic arm_transfer(input int unsigned bytes_value,input int unsigned dir_value);
    transfer_enabled=0;nbytes=bytes_value;direction=dir_value;
    sampled_bits=0;edge_count=0;transfers++;sd_i=0;
    previous_sck=sck;transfer_enabled=1;
    $display("[SPI_TX_ENABLE_TRANSFER] case=%0d ordinal=%0d mode=%0d div=%0d cs=%0d bytes=%0d direction=%0d",
      case_id,transfers,spi_mode,spi_div,selected_cs,nbytes,direction);
  endtask
  task automatic put_tx(input int unsigned start_index,input int unsigned count);
    int unsigned i,amount;
    logic [31:0] word_value;
    i=0;
    while(i<count)begin
      amount=count-i;if(amount>4)amount=4;
      // Three-byte strobes are unsupported by this fixed controller: split 2+1.
      if(amount==3)amount=2;
      word_value=0;
      for(int unsigned j=0;j<amount;j++)word_value[8*j+:8]=tx_pattern(start_index+i+j);
      wr(TXDATA,word_value,4'((1<<amount)-1));i+=amount;
    end
  endtask
  task automatic drain_rx(input int unsigned count);
    logic [31:0] value,gold,mask;
    int unsigned amount;
    for(int unsigned i=0;i<count;i+=4)begin
      do rd(STATUS,value);while(value[15:8]==0);
      rd(RXDATA,value);gold=0;amount=count-i;if(amount>4)amount=4;
      for(int unsigned j=0;j<amount;j++)gold[8*j+:8]=rx_pattern(i+j);
      mask=amount==4?'1:((32'h1<<(8*amount))-1);
      check($sformatf("rx_%0d",i),value,gold,mask);
    end
  endtask
  task automatic finish_transfer;
    logic [31:0] s;
    wait(sampled_bits>=8*nbytes);
    wait(csb===3'b111);
    status_wait(32'h40000000,0);rd(ERROR_STATUS,s);check("normal_error_status",s,0,'h3f);
    transfer_enabled=0;
    $display("[SPI_TX_ENABLE_TRANSFER_DONE] case=%0d ordinal=%0d sample_bits=%0d edges=%0d",case_id,transfers,sampled_bits,edge_count);
  endtask
  task automatic normal_transfer(input int unsigned count,input int unsigned dir_value);
    arm_transfer(count,dir_value);
    if(dir_value&2)put_tx(0,count);
    wr(COMMAND,(count-1)|(dir_value<<12));wr(CONTROL,Enable);
    if(dir_value&1)drain_rx(count);
    finish_transfer();
  endtask

  // Independent endpoint: CPHA0 presents its first bit before the first edge;
  // CPHA1 changes on leading edges. Both sample MOSI on the opposite edge.
  always @(csb)begin : select_endpoint
    logic [7:0] first_byte;
    if(rst_n && transfer_enabled && csb!==3'b111)begin
      if(csb!==(3'b111 ^ (3'b001<<selected_cs)))fail("multiple or wrong CS asserted");
      if(!(spi_mode&1))begin
        first_byte=rx_pattern(sampled_bits/8);
        sd_i[1]=first_byte[7-(sampled_bits%8)];
      end
    end
  end
  always @(sck)begin : serial_endpoint
    bit leading,sampling;
    logic actual_mosi;
    logic [7:0] wanted;
    int unsigned b;
    if(rst_n && transfer_enabled && csb!==3'b111)begin
      edge_count++;leading=(sck!=logic'(spi_mode>>1));sampling=(spi_mode&1)?!leading:leading;
      $display("[SPI_TX_ENABLE_PIN] case=%0d time_ps=%0d sck=%b cs=%b out=%h oe=%h in=%h sampling=%b bit=%0d",
        case_id,ps(),sck,csb,sd_o,sd_en,sd_i,sampling,sampled_bits);
      if(sampling)begin
        #1ps; // Observe settled output enables after the clock-edge NBA updates.
        wanted=tx_pattern(sampled_bits/8);b=7-(sampled_bits%8);actual_mosi=sd_o[0];
        // The fixed PULP standard-mode contract drives MOSI only for TX bits.
        // Mixed direction 4 has one TX byte followed by one RX byte.
        checks++;
        if((direction&2) || (direction==4 && sampled_bits<8))begin
          if(sd_en[0]!==1'b1)fail("MOSI not enabled during a write sample");
          checks++;
          if(actual_mosi!==wanted[b])fail("MOSI payload mismatch");
        end else if(sd_en[0]!==1'b0)fail("MOSI enabled during a read sample");
        sampled_bits++;
      end else begin
        #1ps;
        if(sampled_bits<8*nbytes)begin
          wanted=rx_pattern(sampled_bits/8);sd_i[1]=wanted[7-(sampled_bits%8)];
        end
      end
    end
    previous_sck=sck;
  end
  // Passive complete pin history, including idle and CS release boundaries.
  // Preserve delta-cycle updates; the independent checker coalesces timestamps.
  always @(rst_n or sck or sck_en or csb or csb_en or sd_o or sd_en or sd_i)
    if(rst_n)
      $display("[SPI_TX_ENABLE_PIN_ALL] case=%0d cycle=%0d time_ps=%0d sck=%b sck_en=%b cs=%b cs_en=%b out=%h oe=%h in=%h",
        case_id,cycle,ps(),sck,sck_en,csb,csb_en,sd_o,sd_en,sd_i);
  always @(posedge clk)begin
    cycle++;
    if(rst_n && transfer_enabled && (dut.tx_stall || dut.rx_stall))
      $display("[SPI_TX_ENABLE_STALL] case=%0d cycle=%0d time_ps=%0d tx=%b rx=%b sck=%b bits=%0d",case_id,cycle,ps(),dut.tx_stall,dut.rx_stall,sck,sampled_bits);
  end

  task automatic mode_profile;
    int unsigned lengths[5]='{1,3,4,5,17};
    int unsigned id,dir;
    id=0;
    for(int unsigned mode_value=0;mode_value<4;mode_value++)
      for(int unsigned d=0;d<3;d++)for(int unsigned l=0;l<5;l++)begin
        dir=d==0?2:(d==1?1:3);
        begin_case("mode",id);configure(mode_value,(id&1)?4:1,id%3);
        normal_transfer(lengths[l],dir);id++;
      end
  endtask
  // A continuous-CS TX-to-RX segment boundary exposed by the SoC read test.
  // Direction 4 labels this mixed two-byte capture; the host checks each role.
  task automatic handoff_profile;
    logic [31:0] value;
    for(int unsigned mode_value=0;mode_value<4;mode_value++)begin
      for(int unsigned variant=0;variant<2;variant++)begin
        begin_case("handoff",400+2*mode_value+variant,variant);
        configure(mode_value,(mode_value&1)?4:1,mode_value%3);
        arm_transfer(2,4);put_tx(0,1);
        wr(COMMAND,(2<<12)|(1<<9));
        if(variant==0)wr(COMMAND,(1<<12));
        wr(CONTROL,Enable);
        if(variant==1)begin
          wait(sampled_bits>=8);status_wait(32'h40000000,0);
          check("gap_selected_cs",{29'd0,csb},32'(7^(1<<(mode_value%3))));
          $display("[SPI_TX_ENABLE_HANDOFF_GAP] case=%0d event=begin cycle=%0d time_ps=%0d sck=%b cs=%b",case_id,cycle,ps(),sck,csb);
          repeat(32)@(negedge clk);
          $display("[SPI_TX_ENABLE_HANDOFF_GAP] case=%0d event=end cycle=%0d time_ps=%0d sck=%b cs=%b",case_id,cycle,ps(),sck,csb);
          wr(COMMAND,(1<<12));
        end
        do rd(STATUS,value);while(value[15:8]==0);
        rd(RXDATA,value);check("rx_0",value,{24'd0,rx_pattern(1)},32'hff);
        finish_transfer();
      end
    end
  endtask
  // Finite interruption of a last-bit TX hold, timed only from public pins.
  // The FF below is observed passively; it never selects the stimulus time.
  task automatic reset_hold_observation(input string stage);
    $display("[SPI_TX_ENABLE_RESET_HOLD] case=%0d ordinal=%0d stage=%s cycle=%0d time_ps=%0d sck=%b cs=%b oe=%h out=%h sw_rst=%b output_en=%b irq_error=%b irq_event=%b",
      case_id,transfers,stage,cycle,ps(),sck,csb,sd_en,sd_o,
      dut.sw_rst,dut.output_en,irq_error,irq_event);
  endtask
  task automatic reset_hold_profile;
    logic [31:0] value;
    for(int unsigned mode_value=0;mode_value<4;mode_value++)begin
      begin_case("reset_hold",500+mode_value);
      // A half SCK period is 64*5ns=320ns. At leading edge 15 the final
      // TX bit is active in every mode. One quarter-period lets the hold
      // settle and leaves three quarters for the real register access.
      configure(mode_value,63,mode_value%3);
      arm_transfer(1,2);put_tx(0,1);wr(COMMAND,(2<<12));wr(CONTROL,Enable);
      wait(edge_count>=15);
      #(((63+1)*5000/4)*1ps);
      reset_hold_observation("before_write");
      // Keep OUTPUT_EN=1: SD disable must follow reset/CS, not output gating.
      wr(CONTROL,32'he0000000);
      transfer_enabled=0;
      $display("[SPI_TX_ENABLE_ABORT] case=%0d ordinal=%0d cycle=%0d time_ps=%0d reason=software_reset sample_bits=%0d edges=%0d",
        case_id,transfers,cycle,ps(),sampled_bits,edge_count);
      repeat(4)@(negedge clk);#1ps;
      reset_hold_observation("after_reset");
      check("reset_mosi_disabled",{28'b0,sd_en},0);
      repeat(2*(63+1))@(negedge clk);#1ps;
      reset_hold_observation("quiet_end");
      rd(CONTROL,value);check("reset_control",value,32'he0000000,32'he0000000);
      rd(STATUS,value);check("reset_empty_idle",value,32'h91000000,32'hfb8fffff);
      // SW_RST clears the queues. Sticky interrupt/error sources use W1C.
      wr(ERROR_STATUS,'h3f);wr(INTR_STATE,3);
      rd(ERROR_STATUS,value);check("reset_error_clear",value,0,'h3f);
      rd(INTR_STATE,value);check("reset_intr_clear",value,0,3);
      wr(CONTROL,0);configure(mode_value,63,mode_value%3);
      normal_transfer(1,1);
    end
  endtask
  task automatic fifo_profile;
    logic [31:0] s;
    logic stopped_sck;
    int unsigned stopped_bits;
    begin_case("tx_starve",100);configure(0,4,0);arm_transfer(8,2);
    wr(COMMAND,7|(2<<12));wr(CONTROL,Enable);
    status_wait(32'h08000000,32'h08000000);
    stopped_sck=sck;stopped_bits=sampled_bits;
    repeat(32)@(posedge clk);
    check("tx_stall_clock",{31'b0,sck},{31'b0,stopped_sck});
    check("tx_stall_samples",sampled_bits,stopped_bits);
    put_tx(0,8);finish_transfer();
    begin_case("rx_full",101);configure(3,4,1);arm_transfer(272,1);
    wr(COMMAND,271|(1<<12));wr(CONTROL,Enable);
    status_wait(32'h02800000,32'h02800000);
    stopped_sck=sck;stopped_bits=sampled_bits;
    repeat(32)@(posedge clk);
    check("rx_stall_clock",{31'b0,sck},{31'b0,stopped_sck});
    check("rx_stall_samples",sampled_bits,stopped_bits);
    drain_rx(272);finish_transfer();
  endtask
  task automatic generate_event(input int unsigned event_id);
    logic [31:0] s;
    case(event_id)
      0:begin arm_transfer(272,1);wr(COMMAND,271|(1<<12));wr(CONTROL,Enable|(2<<8)|2);status_wait('h02800000,'h02800000);end
      1:begin arm_transfer(8,2);wr(COMMAND,7|(2<<12));wr(CONTROL,Enable|(2<<8)|2);status_wait('h10000000,'h10000000);end
      2:begin arm_transfer(12,1);wr(COMMAND,11|(1<<12));wr(CONTROL,Enable|(2<<8)|2);status_wait('h00100000,'h00100000);end
      3:begin arm_transfer(16,2);wr(COMMAND,15|(2<<12));wr(CONTROL,Enable|(2<<8)|2);status_wait('h04000000,'h04000000);end
      4:begin arm_transfer(4,0);wr(CONTROL,Enable|(2<<8)|2);status_wait('h80000000,'h80000000);end
      5:begin arm_transfer(4,2);wr(COMMAND,3|(2<<12));wr(CONTROL,Enable|(2<<8)|2);wait(sampled_bits>=32);status_wait('h40000000,0);end
    endcase
  endtask
  task automatic event_profile;
    logic [31:0] state;
    for(int unsigned ev=0;ev<6;ev++)for(int unsigned repetition=0;repetition<2;repetition++)begin
      begin_case("event",200+ev,ev,repetition);configure(0,4,0,(2<<8)|2);
      // Establish the opposite state before enabling each edge detector.
      if(ev==1)put_tx(0,8);
      if(ev==3)put_tx(0,16);
      if(ev==5)put_tx(0,4);
      if(ev==4)for(int i=0;i<4;i++)wr(COMMAND,7);
      repeat(32)@(posedge clk);wr(INTR_STATE,3);
      wr(EVENT_ENABLE,repetition?(1<<ev):0);
      generate_event(ev);repeat(32)@(posedge clk);
      rd(INTR_STATE,state);check("event_intr_state",state,repetition?2:0,3);
      check("event_irq_masked",{31'b0,irq_event},0);
      if(repetition)begin
        wr(INTR_ENABLE,2);repeat(8)@(posedge clk);check("event_irq_enabled",{31'b0,irq_event},1);
        wr(INTR_STATE,2);repeat(8)@(posedge clk);check("event_irq_cleared",{31'b0,irq_event},0);
      end
      if(ev==0)drain_rx(272);
      if(ev==2)drain_rx(12);
      finish_transfer();wr(EVENT_ENABLE,0);wr(INTR_ENABLE,0);wr(INTR_STATE,3);
      configure(0,4,0);normal_transfer(5,3);
    end
  endtask
  task automatic error_profile;
    logic [31:0] value,expected_bit;
    bit expected_irq;
    for(int unsigned variant=0;variant<8;variant++)for(int unsigned mask_value=0;mask_value<2;mask_value++)begin
      begin_case("error",300+2*variant+mask_value,variant,mask_value);configure(0,4,0);
      wr(ERROR_ENABLE,mask_value?'h1f:0);wr(INTR_ENABLE,0);wr(INTR_STATE,3);
      case(variant)
        0:begin for(int i=0;i<5;i++)wr(COMMAND,0);expected_bit=1;end
        1:begin for(int i=0;i<74;i++)wr(TXDATA,32'(i));expected_bit=2;end
        2:begin rd(RXDATA,value);expected_bit=4;end
        3:begin wr(COMMAND,(3<<10)|(1<<12));expected_bit=8;end
        4:begin wr(COMMAND,(1<<10)|(3<<12));expected_bit=8;end
        5:begin wr(COMMAND,(2<<10)|(3<<12));expected_bit=8;end
        6:begin wr(CSID,3);wr(COMMAND,(1<<12));expected_bit=16;end
        7:begin wr(TXDATA,32'h76543210,4'b0101);expected_bit=32;end
      endcase
      repeat(16)@(posedge clk);rd(ERROR_STATUS,value);check("error_status",value,expected_bit,'h3f);
      expected_irq=mask_value || variant==7;
      rd(INTR_STATE,value);check("error_intr_state",value,expected_irq?1:0,3);
      check("error_irq_masked",{31'b0,irq_error},0);
      wr(INTR_ENABLE,1);repeat(8)@(posedge clk);check("error_irq_enabled",{31'b0,irq_error},32'(expected_irq));
      wr(ERROR_STATUS,expected_bit);wr(INTR_STATE,1);repeat(8)@(posedge clk);
      rd(ERROR_STATUS,value);check("error_status_cleared",value,0,'h3f);
      check("error_irq_cleared",{31'b0,irq_error},0);
      if(variant!=2 && variant!=7)reset_core();
      configure(0,4,0);normal_transfer(5,3);
    end
  endtask
  initial begin
    void'($value$plusargs("SPI_TX_ENABLE_PROFILE=%s",profile));
    $display("[SPI_TX_ENABLE_PROFILE] kind=unit profile=%s version=1",profile);
    #100ns;@(negedge clk);rst_n=1;repeat(16)@(posedge clk);
    case(profile)
      "mode":mode_profile();"fifo":fifo_profile();"event":event_profile();"error":error_profile();"handoff":handoff_profile();
      "reset_hold":reset_hold_profile();
      default:$fatal(1,"Unsupported SPI_TX_ENABLE_PROFILE %s",profile);
    endcase
    reset_core();
    $display("[SPI_TX_ENABLE_DONE] kind=unit profile=%s cases=%0d transfers=%0d checks=%0d errors=%0d mmio=%0d",profile,cases,transfers,checks,errors,mmio_count);
    if(errors)$fatal(1,"SPI_TX_ENABLE functional errors");
    $finish;
  end
  initial begin #5ms;$fatal(1,"SPI_HDL_LIMIT");end
endmodule

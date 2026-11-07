// Copyright 2026 CheshireAra contributors.
// SPDX-License-Identifier: Apache-2.0
// Finite real-module PLIC test with an independent transaction reference.
// The reference model uses bus transactions and source inputs, not DUT winners.
module tb_e_plic_unit;
  timeunit 1ns;
  timeprecision 1ps;

  localparam int NSRC = 58;
  localparam int NTGT = 2;
  localparam int NPHASE = 12;
  localparam int P_IDLE = 0, P_DISABLED = 1, P_CONSECUTIVE = 2, P_ZERO = 3;
  localparam int P_SINGLE = 4, P_PAIR = 5, P_CONTEXT = 6, P_GATEWAY = 7;
  localparam int P_CC = 8, P_RESET = 9;
  localparam int P_THRESHOLD = 10;
  localparam int P_ALL_SOURCE = 11;
  localparam logic [31:0] IP_LO = 'h1000, IP_HI = 'h1004;
  localparam logic [31:0] IE0_LO = 'h2000, IE0_HI = 'h2004;
  localparam logic [31:0] IE1_LO = 'h2080, IE1_HI = 'h2084;
  localparam logic [31:0] TH0 = 'h200000, CC0 = 'h200004;
  localparam logic [31:0] TH1 = 'h201000, CC1 = 'h201004;

  typedef struct packed {
    logic valid;
    logic write;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [3:0] wstrb;
  } reg_req_t;
  typedef struct packed {
    logic ready;
    logic error;
    logic [31:0] rdata;
  } reg_rsp_t;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [NSRC-1:0] sources = '0;
  reg_req_t req = '0;
  reg_rsp_t rsp;
  logic [NTGT-1:0] irq;
  logic [5:0] irq_id [NTGT];
  logic [NTGT-1:0] msip;

  rv_plic #(.reg_req_t(reg_req_t), .reg_rsp_t(reg_rsp_t)) dut (
    .clk_i(clk), .rst_ni(rst_n), .reg_req_i(req), .reg_rsp_o(rsp),
    .intr_src_i(sources), .irq_o(irq), .irq_id_o(irq_id), .msip_o(msip)
  );
  always #5ns clk = ~clk;

  logic [NSRC-1:0] ref_meta = '0, ref_sync = '0;
  logic [NSRC-1:0] ref_pending = '0, ref_busy = '0, ref_ip_csr = '0;
  logic [NSRC-1:0] ref_enable [NTGT];
  logic [NSRC-1:0][2:0] ref_priority = '0;
  logic [2:0] ref_threshold [NTGT];
  logic [NTGT-1:0] ref_irq = '0;
  logic [5:0] ref_irq_id [NTGT];
  longint unsigned cycles = 0, checks = 0, errors = 0, vectors = 0;
  longint unsigned phase_checks [NPHASE];
  longint unsigned phase_errors [NPHASE];
  longint unsigned phase_vectors [NPHASE];
  int phase = P_IDLE;
  bit finished = 0;
  string profile = "full";

  function automatic string phase_name(input int value);
    case (value)
      P_IDLE: return "idle";
      P_DISABLED: return "probe_disabled_complete";
      P_CONSECUTIVE: return "probe_back_to_back_claim";
      P_ZERO: return "probe_priority_zero";
      P_SINGLE: return "single_priority_threshold";
      P_PAIR: return "pair_priority_arbitration";
      P_CONTEXT: return "context_independence";
      P_GATEWAY: return "level_gateway_completion";
      P_CC: return "claim_sequences";
      P_RESET: return "reset";
      P_THRESHOLD: return "threshold_boundary";
      P_ALL_SOURCE: return "all_source_arbitration";
      default: return "unknown";
    endcase
  endfunction

  // Generic max-tree semantics differ from architectural claim eligibility:
  // a valid input with priority zero is still a valid input to this raw tree.
  function automatic int raw_winner(input logic [NSRC-1:0] pending, enabled,
                                    input logic [NSRC-1:0][2:0] priorities);
    bit found;
    int selected;
    int best_priority;
    found = 0;
    selected = 0;
    best_priority = 0;
    for (int source = 0; source < NSRC; source++) begin
      if (pending[source] && enabled[source]) begin
        if (!found || int'(priorities[source]) > best_priority) begin
          found = 1;
          selected = source;
          best_priority = int'(priorities[source]);
        end
      end
    end
    return selected;
  endfunction

  task automatic check_value(input bit ok, input string label,
                             input logic [63:0] expected, actual);
    checks++;
    phase_checks[phase]++;
    if (!ok) begin
      errors++;
      phase_errors[phase]++;
      if (phase_errors[phase] == 1 || errors <= 24)
        $display("E_PLIC_ERROR phase=%s label=%s cycle=%0d expected=%016h actual=%016h",
                 phase_name(phase), label, cycles, expected, actual);
    end
  endtask

  task automatic start_vector;
    vectors++;
    phase_vectors[phase]++;
  endtask

  // An ascending linear search is independent of the DUT's binary max tree.
  // Priority zero disables architectural claim eligibility. Threshold is absent.
  function automatic int winner(input logic [NSRC-1:0] pending, enabled,
                                input logic [NSRC-1:0][2:0] priorities);
    int selected;
    int best_priority;
    selected = 0;
    best_priority = 0;
    for (int source = 1; source < NSRC; source++) begin
      if (pending[source] && enabled[source] && int'(priorities[source]) > best_priority) begin
        selected = source;
        best_priority = int'(priorities[source]);
      end
    end
    return selected;
  endfunction

  function automatic logic [31:0] cc_address(input int target);
    return target == 0 ? CC0 : CC1;
  endfunction

  function automatic logic [NSRC-1:0] source_mask(input int a, input int b = 0);
    logic [NSRC-1:0] value;
    value = '0;
    if (a > 0 && a < NSRC) value[a] = 1'b1;
    if (b > 0 && b < NSRC) value[b] = 1'b1;
    return value;
  endfunction

  // This monitor samples transactions in the active region at the accepting
  // edge. The DUT has not applied its NBA updates. Drivers change only at negedge.
  always @(posedge clk or negedge rst_n) begin : reference_monitor
    logic [NSRC-1:0] claim, complete, next_pending, next_busy;
    logic [NTGT-1:0] next_irq;
    logic [5:0] next_id [NTGT];
    logic [31:0] address, expected_read;
    bit known_read;
    int selected, target, completed_source;
    if (clk === 1'b1) cycles++;
    if (!rst_n) begin
      ref_meta = '0;
      ref_sync = '0;
      ref_pending = '0;
      ref_busy = '0;
      ref_ip_csr = '0;
      ref_priority = '0;
      ref_irq = '0;
      for (int t = 0; t < NTGT; t++) begin
        ref_enable[t] = '0;
        ref_threshold[t] = '0;
        ref_irq_id[t] = '0;
      end
    end else begin
      claim = '0;
      complete = '0;
      address = req.addr;
      expected_read = '0;
      known_read = 1'b0;
      check_value(sources[0] === 1'b0, "reserved_source_zero", 0, sources[0]);
      if (req.valid) begin
        check_value(rsp.ready === 1'b1, "bus_ready", 1, rsp.ready);
        check_value(rsp.error === 1'b0, "bus_error", 0, rsp.error);
        check_value(req.wstrb === 4'hf, "full_word_access", 15, req.wstrb);
        if (!req.write) begin
          if (address <= 4*(NSRC-1) && address[1:0] == 0) begin
            expected_read = 32'(ref_priority[address >> 2]);
            known_read = 1;
          end
          case (address)
            IP_LO: begin expected_read = ref_ip_csr[31:0]; known_read = 1; end
            IP_HI: begin expected_read = {6'b0, ref_ip_csr[57:32]}; known_read = 1; end
            IE0_LO: begin expected_read = ref_enable[0][31:0]; known_read = 1; end
            IE0_HI: begin expected_read = {6'b0, ref_enable[0][57:32]}; known_read = 1; end
            IE1_LO: begin expected_read = ref_enable[1][31:0]; known_read = 1; end
            IE1_HI: begin expected_read = {6'b0, ref_enable[1][57:32]}; known_read = 1; end
            TH0: begin expected_read = 32'(ref_threshold[0]); known_read = 1; end
            TH1: begin expected_read = 32'(ref_threshold[1]); known_read = 1; end
            CC0, CC1: begin
              target = (address == CC0) ? 0 : 1;
              selected = winner(ref_pending, ref_enable[target], ref_priority);
              expected_read = 32'(selected);
              known_read = 1;
              if (selected != 0) claim[selected] = 1;
            end
            default: ;
          endcase
          check_value(known_read, "known_read_address", 1, known_read);
          check_value(rsp.rdata === expected_read, "register_read", expected_read, rsp.rdata);
        end else if (address == CC0 || address == CC1) begin
          target = (address == CC0) ? 0 : 1;
          completed_source = int'(req.wdata[5:0]);
          if (completed_source > 0 && completed_source < NSRC
              && ref_enable[target][completed_source]) complete[completed_source] = 1;
        end
      end

      // Notification uses old pending/configuration. Its outputs register once.
      for (int t = 0; t < NTGT; t++) begin
        selected = winner(ref_pending, ref_enable[t], ref_priority);
        next_id[t] = 6'(selected);
        next_irq[t] = selected != 0 && ref_priority[selected] > ref_threshold[t];
      end
      next_pending = ref_pending;
      next_busy = ref_busy;
      for (int source = 1; source < NSRC; source++) begin
        if (!ref_pending[source] && !ref_busy[source] && ref_sync[source])
          next_pending[source] = 1;
        if (ref_pending[source] && claim[source]) next_pending[source] = 0;
        if (!ref_busy[source] && ref_sync[source]) next_busy[source] = 1;
        else if (ref_busy[source] && !ref_pending[source] && complete[source])
          next_busy[source] = 0;
      end
      // The IP readback CSR has a further register; it captures old gateway IP.
      ref_ip_csr = ref_pending;
      ref_pending = next_pending;
      ref_busy = next_busy;
      ref_sync = ref_meta;
      ref_meta = sources;
      ref_irq = next_irq;
      for (int t = 0; t < NTGT; t++) ref_irq_id[t] = next_id[t];
      // Configuration writes do not affect the notification sampled at this edge.
      if (req.valid && req.write) begin
        if (address <= 4*(NSRC-1) && address[1:0] == 0)
          ref_priority[address >> 2] = req.wdata[2:0];
        case (address)
          IE0_LO: ref_enable[0][31:0] = req.wdata;
          IE0_HI: ref_enable[0][57:32] = req.wdata[25:0];
          IE1_LO: ref_enable[1][31:0] = req.wdata;
          IE1_HI: ref_enable[1][57:32] = req.wdata[25:0];
          TH0: ref_threshold[0] = req.wdata[2:0];
          TH1: ref_threshold[1] = req.wdata[2:0];
          default: ;
        endcase
      end
    end
    // Observe registered state after NBA, before the next driver edge.
    #1ns;
    check_value(irq === ref_irq, "registered_notification", ref_irq, irq);
    for (int t = 0; t < NTGT; t++) begin
      check_value(!$isunknown(irq_id[t]), "known_notification_id", 0, irq_id[t]);
      if (ref_irq[t]) check_value(irq_id[t] === ref_irq_id[t], "notified_winner", ref_irq_id[t], irq_id[t]);
    end
    check_value(dut.u_gateway.ip_o === ref_pending, "global_pending", ref_pending, dut.u_gateway.ip_o);
    check_value(dut.u_gateway.ia === ref_busy, "global_busy", ref_busy, dut.u_gateway.ia);
    check_value(msip === '0, "unused_msip_zero", 0, msip);
  end

  // The generated hierarchy index is constant at elaboration. These checks use
  // current post-NBA reference inputs, independently of the registered IRQ path.
  for (genvar target = 0; target < NTGT; target++) begin : check_raw_tree
    always @(posedge clk) begin : raw_tree_monitor
      logic expected_valid;
      logic [2:0] expected_value;
      int selected;
      #1ns;
      expected_valid = |(ref_pending & ref_enable[target]);
      selected = raw_winner(ref_pending,ref_enable[target],ref_priority);
      expected_value = expected_valid ? ref_priority[selected] : ref_priority[0];
      check_value(dut.gen_target[target].u_target.u_prim_max_tree.max_valid_o === expected_valid,
                  "raw_tree_valid",expected_valid,
                  dut.gen_target[target].u_target.u_prim_max_tree.max_valid_o);
      check_value(dut.gen_target[target].u_target.u_prim_max_tree.max_value_o === expected_value,
                  "raw_tree_value",expected_value,
                  dut.gen_target[target].u_target.u_prim_max_tree.max_value_o);
      check_value(dut.gen_target[target].u_target.u_prim_max_tree.max_idx_o === 6'(selected),
                  "raw_tree_lowest_max_id",selected,
                  dut.gen_target[target].u_target.u_prim_max_tree.max_idx_o);
    end
  end

  task automatic wait_cycles(input int count);
    repeat (count) @(negedge clk);
  endtask

  task automatic reset_dut(input int new_phase, input bit clear_sources = 1);
    @(negedge clk);
    req = '0;
    if (clear_sources) sources = '0;
    phase = new_phase;
    rst_n = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
  endtask

  task automatic transfer(input bit write_access, input logic [31:0] address, data,
                          output logic [31:0] read_data);
    @(negedge clk);
    req = '{valid:1'b1, write:write_access, addr:address, wdata:data, wstrb:4'hf};
    @(posedge clk);
    // This read must stay before any delay, event wait, or NBA observation.
    read_data = rsp.rdata;
    @(negedge clk);
    req = '0;
  endtask

  task automatic write32(input logic [31:0] address, data);
    logic [31:0] unused;
    transfer(1, address, data, unused);
  endtask

  task automatic read32(input logic [31:0] address, output logic [31:0] data);
    transfer(0, address, 0, data);
  endtask

  task automatic read_consecutive(input int first_target, second_target,
                                  output logic [31:0] first_data, second_data);
    @(negedge clk);
    req = '{valid:1'b1, write:1'b0, addr:cc_address(first_target), wdata:32'b0, wstrb:4'hf};
    @(posedge clk);
    first_data = rsp.rdata;
    @(negedge clk);
    // Keep valid asserted: these are two adjacent accepting edges, with no bubble.
    req.addr = cc_address(second_target);
    @(posedge clk);
    second_data = rsp.rdata;
    @(negedge clk);
    req = '0;
  endtask

  task automatic enable_targets(input logic [NSRC-1:0] machine, supervisor);
    write32(IE0_LO, machine[31:0]);
    write32(IE0_HI, {6'b0, machine[57:32]});
    write32(IE1_LO, supervisor[31:0]);
    write32(IE1_HI, {6'b0, supervisor[57:32]});
  endtask

  task automatic configure(input int a, p_a, b, p_b, t_machine, t_supervisor,
                           input logic [NSRC-1:0] machine, supervisor);
    write32(32'(4*a), 32'(p_a));
    if (b != 0) write32(32'(4*b), 32'(p_b));
    enable_targets(machine, supervisor);
    write32(TH0, 32'(t_machine));
    write32(TH1, 32'(t_supervisor));
  endtask

  task automatic drive_sources(input logic [NSRC-1:0] value);
    @(negedge clk);
    sources = value;
  endtask

  task automatic pending_readback;
    logic [31:0] value;
    read32(IP_LO, value);
    read32(IP_HI, value);
  endtask

  task automatic report_phase(input int which);
    $display("E_PLIC_PHASE name=%s vectors=%0d checks=%0d errors=%0d",
             phase_name(which), phase_vectors[which], phase_checks[which], phase_errors[which]);
  endtask

  task automatic probe_disabled_complete;
    logic [31:0] value;
    reset_dut(P_DISABLED);
    start_vector();
    configure(1, 3, 0, 0, 0, 0, source_mask(1), '0);
    drive_sources(source_mask(1)); wait_cycles(6);
    read32(CC0, value);
    check_value(value === 32'd1, "probe_initial_claim", 1, value);
    wait_cycles(3);
    write32(CC1, 1); // S has IE[1]=0: this completion must be ignored.
    wait_cycles(5);
    pending_readback();
    read32(CC0, value);
    check_value(value === 32'd0, "disabled_completion_did_not_rearm", 0, value);
    report_phase(P_DISABLED);
  endtask

  task automatic probe_back_to_back_claim;
    logic [31:0] first_value, second_value;
    reset_dut(P_CONSECUTIVE);
    start_vector();
    configure(1, 5, 0, 0, 0, 0, source_mask(1), source_mask(1));
    drive_sources(source_mask(1)); wait_cycles(6);
    read_consecutive(0, 1, first_value, second_value);
    check_value(first_value === 32'd1, "first_consecutive_claim", 1, first_value);
    check_value(second_value === 32'd0, "second_consecutive_claim_consumed_once", 0, second_value);
    wait_cycles(3);
    report_phase(P_CONSECUTIVE);
  endtask

  task automatic probe_priority_zero;
    logic [31:0] value;
    reset_dut(P_ZERO);
    start_vector();
    configure(1, 0, 0, 0, 0, 7, source_mask(1), source_mask(1));
    drive_sources(source_mask(1)); wait_cycles(6);
    read32(CC0, value);
    check_value(value === 32'd0, "priority_zero_not_claimable", 0, value);
    pending_readback();
    write32(4, 5); // The retained event becomes claimable after re-prioritization.
    wait_cycles(3);
    read32(CC1, value);
    check_value(value === 32'd1, "zero_priority_pending_retained", 1, value);
    report_phase(P_ZERO);
  endtask

  task automatic run_probes;
    probe_disabled_complete();
    probe_back_to_back_claim();
    probe_priority_zero();
  endtask

  task automatic single_matrix;
    // 2 targets * 57 legal IDs * 8 priorities = 912 vectors.
    // Source stays pending during each priority sweep. Only one context is enabled.
    for (int target = 0; target < NTGT; target++)
      for (int source = 1; source < NSRC; source++) begin
        reset_dut(P_SINGLE);
        configure(source,0,0,0,0,0,target==0 ? source_mask(source) : '0,
                  target==1 ? source_mask(source) : '0);
        drive_sources(source_mask(source)); wait_cycles(6);
        for (int p_value = 0; p_value <= 7; p_value++) begin
          write32(32'(4*source),32'(p_value)); wait_cycles(2); start_vector();
        end
      end
    report_phase(P_SINGLE);
  endtask

  task automatic pair_matrix;
    // 2 targets * C(57,2) * 8 * 8 = 204288 vectors, including both zero,
    // every equal-priority pair and both priority orderings. CC is tested separately.
    for (int target = 0; target < NTGT; target++)
      for (int a = 1; a < NSRC; a++)
        for (int b = a+1; b < NSRC; b++) begin
          reset_dut(P_PAIR);
          configure(a,0,b,0,0,0,target==0 ? source_mask(a,b) : '0,
                    target==1 ? source_mask(a,b) : '0);
          drive_sources(source_mask(a,b)); wait_cycles(6);
          for (int p_a = 0; p_a <= 7; p_a++)
            for (int p_b = 0; p_b <= 7; p_b++) begin
              write32(32'(4*a),32'(p_a)); write32(32'(4*b),32'(p_b));
              wait_cycles(2); start_vector();
            end
          end
    report_phase(P_PAIR);
  endtask

  task automatic threshold_matrix;
    int source;
    for (int target = 0; target < NTGT; target++)
      for (int boundary = 0; boundary < 4; boundary++) begin
        case (boundary)
          0: source=1;
          1: source=31;
          2: source=32;
          default: source=57;
        endcase
        // Independently enumerate IP/IE = 00,01,10,11. Raw level is held
        // either low or high after a fresh reset to obtain the requested IP.
        for (int pending_enable = 0; pending_enable < 4; pending_enable++) begin
          reset_dut(P_THRESHOLD);
          configure(source,0,0,0,0,0,
                    target==0 && pending_enable[0] ? source_mask(source) : '0,
                    target==1 && pending_enable[0] ? source_mask(source) : '0);
          drive_sources(pending_enable[1] ? source_mask(source) : '0); wait_cycles(6);
          for (int p_value = 0; p_value <= 7; p_value++) begin
            write32(32'(4*source),32'(p_value));
            for (int threshold = 0; threshold <= 7; threshold++) begin
              write32(target==0 ? TH0 : TH1,32'(threshold));
              wait_cycles(2); start_vector();
            end
          end
        end
      end
    report_phase(P_THRESHOLD);
  endtask

  task automatic all_source_matrix;
    logic [NSRC-1:0] all_sources;
    int previous_highest;
    all_sources = '1;
    all_sources[0] = 0;
    for (int target = 0; target < NTGT; target++) begin
      reset_dut(P_ALL_SOURCE);
      enable_targets(target==0 ? all_sources : '0,target==1 ? all_sources : '0);
      drive_sources(all_sources); wait_cycles(6);
      // All 57 legal sources are pending and enabled at each equal level 0..7.
      for (int p_value = 0; p_value <= 7; p_value++) begin
        for (int source = 1; source < NSRC; source++)
          write32(32'(4*source),32'(p_value));
        wait_cycles(2); start_vector();
      end
      // Keep every other source pending at positive priority 1. Each source,
      // including the partial final tree leaf, becomes the unique priority-7 max.
      for (int source = 1; source < NSRC; source++) write32(32'(4*source),1);
      previous_highest=0;
      for (int source = 1; source < NSRC; source++) begin
        if (previous_highest!=0) write32(32'(4*previous_highest),1);
        write32(32'(4*source),7);
        wait_cycles(2); start_vector();
        previous_highest=source;
      end
    end
    report_phase(P_ALL_SOURCE);
  endtask

  task automatic context_matrix;
    int a, b, p_a, p_b;
    logic [NSRC-1:0] machine, supervisor;
    for (int boundary = 0; boundary < 4; boundary++) begin
      case (boundary)
        0: begin a=1; b=2; end
        1: begin a=31; b=32; end
        2: begin a=32; b=57; end
        default: begin a=1; b=57; end
      endcase
      for (int order = 0; order < 2; order++) begin
        p_a = order ? 6 : 3; p_b = order ? 3 : 6;
        reset_dut(P_CONTEXT);
        configure(a,p_a,b,p_b,0,0,'0,'0);
        drive_sources(source_mask(a,b)); wait_cycles(6);
        for (int enables = 0; enables < 16; enables++) begin
          machine='0; supervisor='0;
          machine[a]=enables[0]; machine[b]=enables[1];
          supervisor[a]=enables[2]; supervisor[b]=enables[3];
          enable_targets(machine,supervisor);
          for (int t_m = 0; t_m <= 7; t_m++) begin
            write32(TH0,32'(t_m));
            for (int t_s = 0; t_s <= 7; t_s++) begin
              write32(TH1,32'(t_s)); wait_cycles(2); start_vector();
            end
          end
        end
      end
    end
    report_phase(P_CONTEXT);
  endtask

  task automatic gateway_matrix;
    logic [31:0] value;
    int other;
    for (int source = 1; source < NSRC; source++) begin
      other = source == 57 ? 1 : source+1;
      // Falling level does not retract a latched pending event. After claim,
      // pulses during service are not queued; valid completion releases busy.
      reset_dut(P_GATEWAY); start_vector();
      configure(source,3,0,0,0,0,source_mask(source),source_mask(source));
      drive_sources(source_mask(source)); wait_cycles(6);
      drive_sources('0); wait_cycles(6); pending_readback();
      write32(CC1,32'(source)); // Completion before claim cannot erase pending.
      read32(CC0,value); check_value(value===32'(source),"latched_level_claim",source,value);
      drive_sources(source_mask(source)); wait_cycles(6);
      drive_sources('0); wait_cycles(6);
      read32(CC1,value); check_value(value===0,"no_service_pulse_queue",0,value);
      write32(CC1,32'(source)); wait_cycles(4); pending_readback();
      write32(CC0,32'(source)); // Duplicate complete with low level and no active event.
      wait_cycles(4); pending_readback();
      read32(CC0,value); check_value(value===0,"duplicate_idle_complete_no_event",0,value);
      drive_sources(source_mask(source)); wait_cycles(6);
      read32(CC1,value); check_value(value===32'(source),"new_level_after_completion",source,value);

      // Both enabled contexts may complete the one shared source. Threshold
      // blocks notification, not claim/completion. Held level re-pends once.
      reset_dut(P_GATEWAY); start_vector();
      configure(source,4,0,0,7,7,source_mask(source),source_mask(source));
      drive_sources(source_mask(source)); wait_cycles(6);
      read32(CC0,value); wait_cycles(3);
      write32(CC1,32'(source)); wait_cycles(5); pending_readback();
      read32(CC1,value); check_value(value===32'(source),"enabled_cross_context_completion",source,value);
      wait_cycles(3); read32(CC0,value); check_value(value===0,"held_level_only_one_pending",0,value);

      // Neither invalid encoded IDs nor an inactive legal ID may release this
      // source. All six-bit out-of-range IDs are exercised from both contexts.
      for (int target = 0; target < NTGT; target++) begin
        write32(cc_address(target),0);
        for (int invalid_id = 58; invalid_id < 64; invalid_id++)
          write32(cc_address(target),32'(invalid_id));
        write32(cc_address(target),32'(other));
      end
      wait_cycles(5); pending_readback();
      read32(CC0,value); check_value(value===0,"invalid_completion_did_not_rearm",0,value);
      write32(CC0,32'(source)); wait_cycles(5);
      write32(CC1,32'(source)); // Duplicate complete while a re-pended event awaits claim.
      wait_cycles(3); pending_readback();
      read32(CC0,value); check_value(value===32'(source),"valid_completion_rearms_level",source,value);

      // Disable after claim: ownership is not sufficient to authorize complete.
      // Re-enabling alone must not release busy; another enabled target may do so.
      reset_dut(P_GATEWAY); start_vector();
      configure(source,5,0,0,0,0,source_mask(source),source_mask(source));
      drive_sources(source_mask(source)); wait_cycles(6); read32(CC0,value);
      enable_targets('0,source_mask(source));
      write32(CC0,32'(source)); wait_cycles(5);
      enable_targets(source_mask(source),source_mask(source)); wait_cycles(4);
      read32(CC0,value); check_value(value===0,"reenable_not_completion",0,value);
      write32(CC1,32'(source)); wait_cycles(5);
      read32(CC0,value); check_value(value===32'(source),"enabled_peer_completion_releases",source,value);
    end
    report_phase(P_GATEWAY);
  endtask

  task automatic claim_matrix;
    logic [31:0] first_value, second_value, value;
    for (int first_target = 0; first_target < NTGT; first_target++)
      for (int second_target = 0; second_target < NTGT; second_target++)
        for (int two_sources = 0; two_sources < 2; two_sources++) begin
          reset_dut(P_CC); start_vector();
          configure(1,5,two_sources ? 57 : 0,3,7,7,
                    source_mask(1,two_sources ? 57 : 0),source_mask(1,two_sources ? 57 : 0));
          drive_sources(source_mask(1,two_sources ? 57 : 0)); wait_cycles(6);
          read_consecutive(first_target,second_target,first_value,second_value);
          check_value(first_value===1,"claim_sequence_first",1,first_value);
          check_value(second_value===32'(two_sources ? 57 : 0),"claim_sequence_second",
                      two_sources ? 57 : 0,second_value);
          wait_cycles(3); read32(cc_address(second_target),value);
          check_value(value===0,"claim_sequence_drained",0,value);
        end
    report_phase(P_CC);
  endtask

  task automatic reset_matrix;
    logic [31:0] value;
    for (int state = 0; state < 4; state++) begin
      reset_dut(P_RESET); start_vector();
      configure(57,7,0,0,0,7,source_mask(57),source_mask(57));
      if (state != 0) begin drive_sources(source_mask(57)); wait_cycles(6); end
      if (state >= 2) begin read32(CC0,value); wait_cycles(3); end
      if (state == 2) begin drive_sources('0); wait_cycles(6); end
      reset_dut(P_RESET,state != 3);
      read32(4*57,value); check_value(value===0,"reset_priority",0,value);
      read32(IE0_LO,value); read32(IE0_HI,value); read32(IE1_LO,value); read32(IE1_HI,value);
      read32(TH0,value); read32(TH1,value); read32(CC0,value); read32(CC1,value);
      pending_readback();
      if (state == 3) begin
        write32(4*57,7); enable_targets(source_mask(57),source_mask(57)); wait_cycles(4);
        read32(CC1,value); check_value(value===57,"held_level_after_reset",57,value);
      end
    end
    report_phase(P_RESET);
  endtask

  initial begin : stimulus
    int probe_failures;
    for (int p=0; p<NPHASE; p++) begin
      phase_checks[p]=0; phase_errors[p]=0; phase_vectors[p]=0;
    end
    if ($value$plusargs("E_PLIC_PROFILE=%s",profile)) begin end
    $display("E_PLIC_START profile=%s sources=58 targets=2 priority_max=7 level_only=1",profile);
    case (profile)
      "full": begin
        run_probes(); single_matrix(); pair_matrix(); all_source_matrix(); threshold_matrix(); context_matrix();
        gateway_matrix(); claim_matrix(); reset_matrix();
      end
      "claim_regression": begin
        probe_back_to_back_claim(); probe_priority_zero();
        single_matrix(); pair_matrix(); all_source_matrix(); threshold_matrix();
        context_matrix(); claim_matrix(); reset_matrix();
      end
      "completion_regression": begin
        probe_disabled_complete(); gateway_matrix(); reset_matrix();
      end
      "probes": run_probes();
      "disabled_complete": probe_disabled_complete();
      "back_to_back_claim": probe_back_to_back_claim();
      "priority_zero": probe_priority_zero();
      default: $fatal(1,"Unknown E_PLIC_PROFILE: %s",profile);
    endcase
    reset_dut(P_IDLE);
    wait_cycles(2);
    probe_failures=int'(phase_errors[P_DISABLED]!=0)+int'(phase_errors[P_CONSECUTIVE]!=0)+int'(phase_errors[P_ZERO]!=0);
    finished=1;
    for (int p=0; p<NPHASE; p++)
      if (phase_vectors[p] != 0)
        $display("E_PLIC_TOTAL phase=%s vectors=%0d checks=%0d errors=%0d",
                 phase_name(p),phase_vectors[p],phase_checks[p],phase_errors[p]);
    $display("E_PLIC_DONE profile=%s vectors=%0d checks=%0d errors=%0d probe_failures=%0d cycles=%0d",
             profile,vectors,checks,errors,probe_failures,cycles);
    if (errors != 0) $fatal(1,"E PLIC functional checks failed");
    $finish;
  end

  initial begin #50ms; $fatal(1,"PLIC_UNIT_TIMEOUT"); end
endmodule

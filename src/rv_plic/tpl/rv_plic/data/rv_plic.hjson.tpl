// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
<% import math %>\
# ${(module_instance_name).upper()} register template
#
# Parameter (given by Python tool)
#  - src:    Number of Interrupt Sources
#  - target: Number of Targets that handle interrupt requests
#  - prio:   Max value of interrupt priorities
#  - module_instance_name: Module instance name.
{
  name:               "${module_instance_name}",
  clock_primary: "clk_i",
  bus_interfaces: [
    { protocol: "reg_iface", direction: "device" }
  ],

  param_list: [
    { name: "NumSrc",
      desc: "Number of interrupt sources",
      type: "int",
      default: "${src}",
      local: "true"
    },
    { name: "NumTarget",
      desc: "Number of Targets (Harts)",
      type: "int",
      default: "${target}",
      local: "true",
    },
    { name: "PrioWidth",
      desc: "Width of priority signals",
      type: "int",
      default: "${(prio).bit_length()}",
      local: "true",
    },
  ],

  // In order to not disturb the PLIC address map, we place the alert test
  // register manually at a safe offset after the main CSRs.
  no_auto_alert_regs: "True",
  alert_list: [
    { name: "fatal_fault",
      desc: '''
      This fatal alert is triggered when a fatal TL-UL bus integrity fault is detected.
      '''
    }
  ],

  inter_signal_list: [
    { struct:  "logic",
      type:    "uni",
      name:    "irq",
      act:     "req",
      package: "",
      width:   "${target}"
    },

    { struct:  "logic",
      type:    "uni",
      name:    "irq_id",
      act:     "req",
      package: "",
    },

    { struct:  "logic",
      type:    "uni",
      name:    "msip",
      act:     "req",
      package: "",
      width:   "${target}"
    },
  ]

  regwidth: "32",
  registers: [
% for i in range(src):
    { name: "PRIO${i}",
      desc: "Interrupt Source ${i} Priority",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "${(prio).bit_length()-1}:0" }
      ],
    }
% endfor
    { skipto: "0x00001000" }
    { multireg: {
        name: "IP",
        desc: "Interrupt Pending",
        count: "NumSrc",
        cname: "${(module_instance_name).upper()}",
        swaccess: "ro",
        hwaccess: "hwo",
        fields: [
          { bits: "0", name: "P", desc: "Interrupt Pending of Source" }
        ],
        tags: [// IP is driven by intr_src, cannot auto-predict
               "excl:CsrNonInitTests:CsrExclCheck"],
      }
    },
% for i in range(target):
    { skipto: "${"0x{:x}".format(0x00002000 + i * 0x80)}" }
    { multireg: {
        name: "IE${i}",
        desc: "Interrupt Enable for Target ${i}",
        count: "NumSrc",
        cname: "${(module_instance_name).upper()}",
        swaccess: "rw",
        hwaccess: "hro",
        fields: [
          { bits: "0", name: "E", desc: "Interrupt Enable of Source" }
        ],
      }
    }
% endfor
% for i in range(target):
    { skipto: "${"0x{:x}".format(0x00200000  + i * 0x1000)}" }
    { name: "THRESHOLD${i}",
      desc: "Threshold of priority for Target ${i}",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "${(prio).bit_length()-1}:0" }
      ],
    }
    { name: "CC${i}",
      desc: '''Claim interrupt by read, complete interrupt by write for Target ${i}.
      Value read/written is interrupt ID. Reading a value of 0 means no pending interrupts.''',
      swaccess: "rw",
      hwaccess: "hrw",
      hwext: "true",
      hwqe: "true",
      hwre: "true",
      fields: [
        { bits: "${(src-1).bit_length()-1}:0" }
      ],
      tags: [// CC register value is related to IP
             "excl:CsrNonInitTests:CsrExclCheck"],
    }
% endfor
  { skipto: "${hex(0x4000000 if nonstd_regs else 0x3FFFFF8)}" }
% for i in range(target if nonstd_regs else 1):
    { name: "MSIP${i}",
      desc: '''msip for Hart ${i}.
      Write 1 to here asserts software interrupt for Hart msip_o[${i}], write 0 to clear.''',
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "0",
          desc: "Software Interrupt Pending register",
        }
      ],
    }
% endfor
  { skipto: "${hex(0x4004000 if nonstd_regs else 0x3FFFFFC)}" }
  { name: "ALERT_TEST",
      desc: '''Alert Test Register.''',
      swaccess: "wo",
      hwaccess: "hro",
      hwqe:     "True",
      hwext:    "True",
      fields: [
        { bits: "0",
          name: "fatal_fault",
          desc: "'Write 1 to trigger one alert event of this kind.'",
        }
      ],
    }
  ],
}

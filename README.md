# OpenTitan Peripherals

A selection of peripherals from lowRISC's [OpenTitan](https://github.com/lowRISC/opentitan) project with adaptations to better integrate with the PULP IP ecosystem. These adaptations were made as part of [Snitch](https://github.com/pulp-platform/snitch) and moved to this repository for greater flexibility. Changes include:

* Use of [`register interface`](https://github.com/pulp-platform/register_interface) and its patched register tool instead of TL/UL.
* Replacement of OpenTitan assertions and some primitives with [`common_cells`](https://github.com/pulp-platform/common_cells).
* Dependency and IP management using [Bender](https://github.com/pulp-platform/bender).
* Minor functional fixes and changes.

This repository uses Bender's `import` command to fully include the remote code in `src` and apply the patches included in `patches`. The IP RTL is pregenerated in its standard configuration, but can be reconfigured in the including project.

## Reconfiguring IPs

To simplify IP reconfiguration in your project, you can include the GNU Make fragment `otp.mk` in your makefile, for example:

```make
include $(bender path opentitan_peripherals)/otp.mk

# Alternative PLIC parameters
PLICOPT = -s 22 -t 1 -p 7

# Alternative SPI host register config
$(OTPROOT)/src/spi_host/data/spi_host.hjson: config/spi_host.json
    cp $< $@

# Rebuild peripheral RTL
all: otp
```

## Adding Patches

After making uncommitted changes to the forked IPs, you can generate a patch for them with:

```
bender import --gen_patch
```

Then rename the generated file to `<next_index>_<patch_description>.patch`. To verify correct patch application:

```
make check_import
```

## Licensing

Unless otherwise noted, everything in this repository is licensed under the Apache License, Version 2.0 (see [LICENSE](https://github.com/pulp-platform/opentitan_peripherals/blob/master/LICENSE) for full text). The copyright for all work included from the OpenTitan project lies with lowRISC contributors.

# Copyright 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Paul Scheffler <paulsc@iis.ee.ethz.ch>

all:

clean:
	rm -rf .bender
	rm -f bender
	rm -f Bender.lock

bender:
	curl --proto '=https' --tlsv1.2 -sSf https://pulp-platform.github.io/bender/init | bash -s -- 0.27.0
	touch bender

# Generate peripheral RTL

BENDER = ./bender
OTPROOT = .
otp.mk: bender # Bender is needed by make fragment
include otp.mk

all: otp

# Checks

CHECK_CLEAN = git status && test -z "$$(git status --porcelain)"

check_generated:
	$(MAKE) -B otp
	$(CHECK_CLEAN)

check_vendor: bender
	./bender vendor --refetch
	$(CHECK_CLEAN)

check: check_generated
check: check_vendor

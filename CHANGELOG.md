# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.4.0 - 2023-05-25
### Fixed
- Correct upstream PLIC register layout to conform with spec.
- Use PULP actions for CI where possible.

## 0.3.1 - 2023-04-11
### Added
- Add `nonstd_regs` parameter to PLIC.

## 0.3.0 - 2023-03-28
### Fixed
- Rebase all hardware to upstream and readapt.
- Add vendored software DIFs for use in dependent projects and adapt.

## 0.2.1 - 2023-01-30
### Fixed
- Eliminate duplicate entry in Bender manifest.

## 0.2.0 - 2023-01-23
### Added
- Fix some bugs in SPI host.
- Update used Bender to 0.27.0.
- Update `register_interface` to 0.3.8, regenerate regfiles.


## 0.1.0 - 2022-09-14
### Added
- Add selected OpenTitan peripherals as Bender import.
- Add existing patches from Snitch repository.
- Add make fragment for easy reconfiguration.

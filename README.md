# Native RMM

![CI Tests](https://github.com/nativeit/nativermm/actions/workflows/ci-tests.yml/badge.svg?branch=develop)
[![codecov](https://codecov.io/gh/nativeit/nativermm/branch/develop/graph/badge.svg?token=8ACUPVPTH6)](https://codecov.io/gh/nativeit/nativermm)
[![Code style: black](https://img.shields.io/badge/code%20style-black-000000.svg)](https://github.com/python/black)

Native RMM is a remote monitoring & management tool, built with Django and Vue.\
It uses an [agent](https://github.com/nativeit/rmmagent) written in golang and integrates with [MeshCentral](https://github.com/Ylianst/MeshCentral)

# [LIVE DEMO](https://demo.nativermm.com/)

Demo database resets every hour. A lot of features are disabled for obvious reasons due to the nature of this app.

### [Discord Chat](https://discord.gg/upGTkWp)

### [Documentation](https://docs.nativermm.com)

## Features

- Teamviewer-like remote desktop control
- Real-time remote shell
- Remote file browser (download and upload files)
- Remote command and script execution (batch, powershell and python scripts)
- Event log viewer
- Services management
- Windows patch management
- Automated checks with email/SMS alerting (cpu, disk, memory, services, scripts, event logs)
- Automated task runner (run scripts on a schedule)
- Remote software installation via chocolatey
- Software and hardware inventory

## Windows agent versions supported

- Windows 7, 8.1, 10, 11, Server 2008R2, 2012R2, 2016, 2019, 2022

## Linux agent versions supported

- Any distro with systemd which includes but is not limited to: Debian (10, 11), Ubuntu x86_64 (18.04, 20.04, 22.04), Synology 7, centos, freepbx and more!

## Mac agent versions supported

- 64 bit Intel and Apple Silicon (M1, M2)

## Installation / Backup / Restore / Usage

### Refer to the [documentation](https://docs.nativermm.com)

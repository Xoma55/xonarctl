# ASUS XONAR AE output switch (Linux)

This utility switches the ASUS XONAR AE between its headphone jack and the
speaker outputs. The card appears as USB device `0b05:180f` and is driven by
the standard `snd-usb-audio` kernel driver. The output relay is controlled by
an ASUS-specific USB Audio 2.0 request, so changing the PipeWire/ALSA default
device does not switch the physical jack.

Подробная инструкция по установке, Secure Boot и ярлыку GNOME на русском — в
[ИНСТРУКЦИЯ_RU.md](./ИНСТРУКЦИЯ_RU.md).

## Build and load

Install kernel development files for the running kernel (Fedora: `kernel-devel`;
Debian/Ubuntu: `linux-headers-$(uname -r)`), then run:

```sh
make
sudo insmod ./snd-xonar-ae.ko
```

The module finds the card by USB ID whenever a command is issued. It does not
claim the audio interfaces, so the standard audio driver remains in place.

## Use

```sh
sudo ./xonarctl status
sudo ./xonarctl speakers
sudo ./xonarctl headphones
sudo ./xonarctl toggle
```

The module exposes the current mode at
`/sys/module/snd_xonar_ae/parameters/output`. Switching requires root because
writing the module parameter sends the USB control request. To load the module
after reboot, install it under `/lib/modules/$(uname -r)/extra/`, run
`sudo depmod -a`, and add `snd-xonar-ae` to `/etc/modules-load.d/xonar-ae.conf`.

Some XONAR AE firmware does not return a usable Connector Control status. In
that case `status` reports the last output successfully requested since the
module was loaded. If the state is still unknown, the first `toggle` selects
speakers; later toggles alternate based on the last successful request.

## Device protocol

The request targets UAC2 Output Terminal 7. `SET_CUR` with Control Selector
`0x08` and payload `01 03` selects speakers; payload `02 03` selects
headphones. A standard Connector Control `GET_CUR` (`CS=0x02`) reports the
active channel count (8 for speakers, 2 for headphones), which the module
uses for `status`.

This protocol is reverse-engineered from Windows-driver USB captures and is
specific to VID:PID `0b05:180f`. The module was not loaded against the live
device in the current development environment because `/dev/snd` is not
exposed here.

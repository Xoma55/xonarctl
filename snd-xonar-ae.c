// SPDX-License-Identifier: GPL-2.0
/* Output relay control for ASUS XONAR AE (USB ID 0b05:180f). */
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/mutex.h>
#include <linux/string.h>
#include <linux/usb.h>

#define XONAR_VENDOR_ID  0x0b05
#define XONAR_PRODUCT_ID 0x180f
#define XONAR_TERMINAL_ID 7

#define XONAR_SET_CUR 0x01
#define XONAR_GET_CUR 0x01
#define XONAR_OUTPUT_CONTROL 0x08
#define XONAR_CONNECTOR_CONTROL 0x02

enum xonar_output {
	XONAR_HEADPHONES,
	XONAR_SPEAKERS,
	XONAR_UNKNOWN,
};

static DEFINE_MUTEX(xonar_lock);
/* Used only when the device does not implement a readable connector state. */
static enum xonar_output xonar_last_requested = XONAR_UNKNOWN;

struct xonar_find_data {
	struct usb_device *device;
};

static int xonar_find_device(struct usb_device *device, void *data)
{
	struct xonar_find_data *found = data;

	if (le16_to_cpu(device->descriptor.idVendor) != XONAR_VENDOR_ID ||
	    le16_to_cpu(device->descriptor.idProduct) != XONAR_PRODUCT_ID)
		return 0;

	found->device = usb_get_dev(device);
	return 1;
}

static struct usb_device *xonar_get_device(void)
{
	struct xonar_find_data found = { };

	usb_for_each_dev(&found, xonar_find_device);
	return found.device;
}

static enum xonar_output xonar_read_output(struct usb_device *device)
{
	/* UAC2 Connector Control data: bNrChannels, bmChannelConfig, iNames. */
	u8 connector[6] = { 0 };
	int ret;

	ret = usb_control_msg(device, usb_rcvctrlpipe(device, 0), XONAR_GET_CUR,
			      USB_DIR_IN | USB_TYPE_CLASS | USB_RECIP_INTERFACE,
			      XONAR_CONNECTOR_CONTROL << 8,
			      XONAR_TERMINAL_ID << 8, connector, sizeof(connector),
			      1000);
	pr_debug("snd-xonar-ae: GET_CUR connector ret=%d data=%*ph\n", ret,
		ret > 0 ? min(ret, (int)sizeof(connector)) : 0, connector);
	if (ret < 1)
		return XONAR_UNKNOWN;

	if (connector[0] == 8)
		return XONAR_SPEAKERS;
	if (connector[0] == 2)
		return XONAR_HEADPHONES;
	return XONAR_UNKNOWN;
}

static int xonar_write_output(struct usb_device *device,
			      enum xonar_output output)
{
	/* ASUS extension: 01 03 selects speakers; 02 03 selects headphones. */
	u8 value[2] = {
		output == XONAR_SPEAKERS ? 0x01 : 0x02,
		0x03,
	};
	int ret;

	ret = usb_control_msg(device, usb_sndctrlpipe(device, 0), XONAR_SET_CUR,
			      USB_DIR_OUT | USB_TYPE_CLASS | USB_RECIP_INTERFACE,
			      XONAR_OUTPUT_CONTROL << 8,
			      XONAR_TERMINAL_ID << 8, value, sizeof(value), 1000);
	pr_debug("snd-xonar-ae: SET_CUR output=%s ret=%d\n",
		output == XONAR_SPEAKERS ? "speakers" : "headphones", ret);
	if (ret < 0)
		return ret;
	return ret == sizeof(value) ? 0 : -EIO;
}

static int xonar_param_get(char *buffer, const struct kernel_param *kp)
{
	struct usb_device *device;
	enum xonar_output output;

	mutex_lock(&xonar_lock);
	device = xonar_get_device();
	if (!device) {
		mutex_unlock(&xonar_lock);
		return -ENODEV;
	}
	output = xonar_read_output(device);
	if (output == XONAR_UNKNOWN)
		output = xonar_last_requested;
	usb_put_dev(device);
	mutex_unlock(&xonar_lock);

	switch (output) {
	case XONAR_SPEAKERS:
		return sysfs_emit(buffer, "speakers\n");
	case XONAR_HEADPHONES:
		return sysfs_emit(buffer, "headphones\n");
	default:
		return sysfs_emit(buffer, "unknown\n");
	}
}

static int xonar_param_set(const char *value, const struct kernel_param *kp)
{
	struct usb_device *device;
	enum xonar_output output;
	char requested[16];
	size_t length = strnlen(value, sizeof(requested));
	int ret;

	if (length == sizeof(requested))
		return -EINVAL;
	strscpy(requested, value, sizeof(requested));
	strim(requested);

	if (!strcmp(requested, "speakers"))
		output = XONAR_SPEAKERS;
	else if (!strcmp(requested, "headphones"))
		output = XONAR_HEADPHONES;
	else
		return -EINVAL;

	mutex_lock(&xonar_lock);
	device = xonar_get_device();
	if (!device) {
		ret = -ENODEV;
		goto unlock;
	}
	ret = xonar_write_output(device, output);
	if (!ret)
		xonar_last_requested = output;
	usb_put_dev(device);
unlock:
	mutex_unlock(&xonar_lock);
	return ret;
}

static const struct kernel_param_ops xonar_param_ops = {
	.get = xonar_param_get,
	.set = xonar_param_set,
};
module_param_cb(output, &xonar_param_ops, NULL, 0644);
MODULE_PARM_DESC(output, "XONAR AE output: speakers or headphones");

MODULE_DESCRIPTION("ASUS XONAR AE headphone/speaker output switch");
MODULE_AUTHOR("OpenAI");
MODULE_LICENSE("GPL");

// eink213v4.c — Waveshare 2.13" V4 e-Paper HAT (SSD1680, 250x122 mono) driver
// for the tiny rootfs: plain C, no Python, no libgpiod, no BCM2835 library.
//
// Two kernel interfaces do all the work:
//   * /dev/spidev0.0            — the pixel/command stream (dtparam=spi=on)
//   * /dev/gpiochipN (v2 ABI)   — RST / DC / PWR outputs, BUSY input
// Both are in the mainline UAPI, so this binary is the whole userland the
// panel needs. Pin numbers are the Waveshare HAT wiring (BCM numbering), the
// same ones pwnagotchi's waveshare_4 driver uses.
//
// Build (cross): aarch64-...-gcc -O2 -static -o eink213 eink213v4.c
// Usage: eink213 [-t] [-c] [-r] [-k] [-2] [-d SPIDEV] [-g CHIP] [LINE...]
//
// Command sequence follows Waveshare's epd2in13_V4 reference driver.

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>
#include <linux/gpio.h>
#include <linux/spi/spidev.h>

#include "font8x16.h"

// Panel geometry. The SSD1680 RAM is addressed in the panel's native portrait
// orientation: 122 px wide (16 bytes, the last 6 bits unused) x 250 px tall.
#define PANEL_W 122
#define PANEL_H 250
#define LINE_B  16                    // bytes per RAM row
#define FB_SIZE (LINE_B * PANEL_H)
// ...but text is laid out in landscape, the way the HAT sits on the Pi.
#define LAND_W  250
#define LAND_H  122

// Waveshare HAT pinout, BCM numbering
#define PIN_RST  17
#define PIN_DC   25
#define PIN_BUSY 24
#define PIN_PWR  18

static int spi_fd = -1, out_fd = -1, in_fd = -1;
static uint8_t fb[FB_SIZE];
static int rot180 = 0;

static void die(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	fprintf(stderr, "eink213: ");
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	if (errno)
		fprintf(stderr, ": %s", strerror(errno));
	fputc('\n', stderr);
	exit(1);
}

static void msleep(long ms)
{
	struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };
	nanosleep(&ts, NULL);
}

// --- GPIO (character device, v2 ABI) --------------------------------------
// Line offsets are requested once and kept open; closing the request fd would
// release the lines and let them float.

enum { O_RST, O_DC, O_PWR, O_COUNT };

static int gpio_open_chip(const char *forced)
{
	if (forced) {
		int fd = open(forced, O_RDONLY);
		if (fd < 0)
			die("open %s", forced);
		return fd;
	}
	// Pick the SoC's own controller: on a Zero 2 W that is pinctrl-bcm2835,
	// on a Pi 4/400 pinctrl-bcm2711 — and on the Pi 4 it is NOT gpiochip0,
	// which belongs to the firmware expander.
	for (int i = 0; i < 8; i++) {
		char path[32];
		struct gpiochip_info info;
		snprintf(path, sizeof(path), "/dev/gpiochip%d", i);
		int fd = open(path, O_RDONLY);
		if (fd < 0)
			continue;
		if (ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &info) == 0 &&
		    strncmp(info.label, "pinctrl-bcm", 11) == 0 && info.lines >= 32)
			return fd;
		close(fd);
	}
	errno = ENODEV;
	die("no pinctrl-bcm* gpiochip found (is this a Raspberry Pi?)");
	return -1;
}

static void gpio_init(const char *chip_path)
{
	int chip = gpio_open_chip(chip_path);
	struct gpio_v2_line_request out = { 0 }, in = { 0 };

	out.offsets[O_RST] = PIN_RST;
	out.offsets[O_DC]  = PIN_DC;
	out.offsets[O_PWR] = PIN_PWR;
	out.num_lines = O_COUNT;
	out.config.flags = GPIO_V2_LINE_FLAG_OUTPUT;
	snprintf(out.consumer, sizeof(out.consumer), "eink213");
	if (ioctl(chip, GPIO_V2_GET_LINE_IOCTL, &out) < 0)
		die("requesting output lines %d/%d/%d", PIN_RST, PIN_DC, PIN_PWR);
	out_fd = out.fd;

	in.offsets[0] = PIN_BUSY;
	in.num_lines = 1;
	in.config.flags = GPIO_V2_LINE_FLAG_INPUT;
	snprintf(in.consumer, sizeof(in.consumer), "eink213");
	if (ioctl(chip, GPIO_V2_GET_LINE_IOCTL, &in) < 0)
		die("requesting BUSY line %d", PIN_BUSY);
	in_fd = in.fd;

	close(chip);
}

static void gpio_set(int idx, int value)
{
	struct gpio_v2_line_values v = { .bits = value ? (1ULL << idx) : 0,
					 .mask = 1ULL << idx };
	if (ioctl(out_fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &v) < 0)
		die("setting gpio line %d", idx);
}

static int gpio_busy(void)
{
	struct gpio_v2_line_values v = { .mask = 1 };
	if (ioctl(in_fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &v) < 0)
		die("reading BUSY");
	return v.bits & 1;
}

// --- SPI ------------------------------------------------------------------

static void spi_init(const char *dev, uint32_t hz)
{
	uint8_t mode = SPI_MODE_0, bits = 8;
	spi_fd = open(dev, O_RDWR);
	if (spi_fd < 0)
		die("open %s (is dtparam=spi=on set and spidev loaded?)", dev);
	if (ioctl(spi_fd, SPI_IOC_WR_MODE, &mode) < 0 ||
	    ioctl(spi_fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
	    ioctl(spi_fd, SPI_IOC_WR_MAX_SPEED_HZ, &hz) < 0)
		die("configuring %s", dev);
}

static void spi_write(const uint8_t *buf, size_t len)
{
	// spidev's default per-transfer buffer is 4096 bytes; a full frame is
	// 4000, but chunking keeps us safe on kernels built with a smaller one
	while (len) {
		size_t n = len > 2048 ? 2048 : len;
		ssize_t w = write(spi_fd, buf, n);
		if (w < 0)
			die("spi write");
		buf += w;
		len -= w;
	}
}

static void cmd(uint8_t c)  { gpio_set(O_DC, 0); spi_write(&c, 1); }
static void dat(uint8_t d)  { gpio_set(O_DC, 1); spi_write(&d, 1); }
static void dat_buf(const uint8_t *b, size_t n) { gpio_set(O_DC, 1); spi_write(b, n); }

static void wait_idle(void)
{
	// BUSY is high while the controller works; a full refresh takes ~2 s
	for (int i = 0; i < 3000; i++) {
		if (!gpio_busy())
			return;
		msleep(10);
	}
	errno = ETIMEDOUT;
	die("panel stayed BUSY for 30 s (check the HAT seating and PWR/BUSY pins)");
}

// --- panel ----------------------------------------------------------------

static void panel_reset(void)
{
	gpio_set(O_RST, 1); msleep(20);
	gpio_set(O_RST, 0); msleep(2);
	gpio_set(O_RST, 1); msleep(20);
}

static void panel_init(void)
{
	gpio_set(O_PWR, 1);           // HAT rev2.3 gates the panel supply here
	msleep(10);
	panel_reset();
	wait_idle();

	cmd(0x12);                    // SWRESET
	wait_idle();

	cmd(0x01);                    // driver output control: 250 gates
	dat(0xf9); dat(0x00); dat(0x00);

	cmd(0x11); dat(0x03);         // data entry: X+ Y+, X counts first

	cmd(0x44);                    // RAM X window, in bytes
	dat(0x00); dat((PANEL_W - 1) >> 3);
	cmd(0x45);                    // RAM Y window, in rows
	dat(0x00); dat(0x00);
	dat((PANEL_H - 1) & 0xff); dat((PANEL_H - 1) >> 8);

	cmd(0x3c); dat(0x05);         // border waveform
	cmd(0x21); dat(0x00); dat(0x80);  // display update control
	cmd(0x18); dat(0x80);         // use the built-in temperature sensor
	wait_idle();
}

static void panel_cursor_home(void)
{
	cmd(0x4e); dat(0x00);
	cmd(0x4f); dat(0x00); dat(0x00);
}

static void panel_show(void)
{
	panel_cursor_home();
	cmd(0x24);                    // write B/W RAM
	dat_buf(fb, FB_SIZE);
	cmd(0x22); dat(0xf7);         // full update sequence
	cmd(0x20);                    // go
	wait_idle();
}

static void panel_sleep(void)
{
	// e-ink must not be left in a powered state: leaving the DC/DC on
	// bakes a ghost image into the panel
	cmd(0x10); dat(0x01);
	msleep(100);
	gpio_set(O_PWR, 0);
}

// --- drawing (landscape coordinates) --------------------------------------

static void fb_clear(void) { memset(fb, 0xff, FB_SIZE); }   // 1 = white

static void px(int lx, int ly, int black)
{
	int x, y;
	if (lx < 0 || lx >= LAND_W || ly < 0 || ly >= LAND_H)
		return;
	// landscape -> panel RAM: a 90 deg rotation, the same mapping
	// PIL's rotate(90, expand=True) performs in the vendor driver
	if (!rot180) {
		x = ly;
		y = LAND_W - 1 - lx;
	} else {
		x = LAND_H - 1 - ly;
		y = lx;
	}
	size_t i = (size_t)y * LINE_B + x / 8;
	uint8_t m = 0x80 >> (x % 8);
	if (black)
		fb[i] &= ~m;
	else
		fb[i] |= m;
}

static void draw_char(int lx, int ly, unsigned char c, int scale)
{
	const unsigned char *g = font8x16 + (size_t)c * FONT_H;
	for (int row = 0; row < FONT_H; row++)
		for (int col = 0; col < FONT_W; col++)
			if (g[row] & (0x80 >> col))
				for (int sy = 0; sy < scale; sy++)
					for (int sx = 0; sx < scale; sx++)
						px(lx + col * scale + sx,
						   ly + row * scale + sy, 1);
}

static void draw_text(int lx, int ly, const char *s, int scale)
{
	for (; *s; s++, lx += FONT_W * scale)
		draw_char(lx, ly, (unsigned char)*s, scale);
}

static void draw_test_pattern(void)
{
	for (int x = 0; x < LAND_W; x++) {         // frame
		px(x, 0, 1);
		px(x, LAND_H - 1, 1);
	}
	for (int y = 0; y < LAND_H; y++) {
		px(0, y, 1);
		px(LAND_W - 1, y, 1);
	}
	for (int y = 8; y < LAND_H - 8; y++)       // checkerboard
		for (int x = 8; x < LAND_W - 8; x++)
			if (((x / 8) + (y / 8)) & 1)
				px(x, y, 1);
	draw_text(16, LAND_H / 2 - 8, " eink213 OK ", 1);
}

// Dump what would be sent to the panel as a PBM, touching no hardware: the
// only way to check the layout without the HAT (and it works on the host).
static void fb_write_pbm(const char *path)
{
	FILE *f = fopen(path, "wb");
	if (!f)
		die("open %s", path);
	fprintf(f, "P4\n%d %d\n", PANEL_W, PANEL_H);
	for (size_t i = 0; i < FB_SIZE; i++)   // PBM: 1 = black, our RAM: 1 = white
		fputc(~fb[i] & 0xff, f);
	if (fclose(f))
		die("write %s", path);
}

static void usage(void)
{
	fputs("Usage: eink213 [-t] [-c] [-r] [-k] [-2] [-d SPIDEV] [-g GPIOCHIP]\n"
	      "               [-o FILE.pbm] [LINE...]\n"
	      "  -t  test pattern (frame + checkerboard) instead of text\n"
	      "  -c  clear the panel to white and exit\n"
	      "  -r  rotate the image 180 degrees\n"
	      "  -k  keep the panel awake (default: deep sleep after the update)\n"
	      "  -2  double-size text (15 columns x 3 rows instead of 31 x 7)\n"
	      "  -d  spidev node   (default /dev/spidev0.0)\n"
	      "  -g  gpiochip node (default: the first pinctrl-bcm* chip)\n"
	      "  -o  render to a PBM file instead of the panel (no hardware needed)\n"
	      "Each LINE is one row of text, 8x16 pixels per character.\n",
	      stderr);
	exit(2);
}

int main(int argc, char **argv)
{
	const char *spidev = "/dev/spidev0.0", *chip = NULL, *pbm = NULL;
	int test = 0, clear = 0, keep = 0, scale = 1, opt;

	while ((opt = getopt(argc, argv, "tcrk2d:g:o:h")) != -1) {
		switch (opt) {
		case 't': test = 1; break;
		case 'c': clear = 1; break;
		case 'r': rot180 = 1; break;
		case 'k': keep = 1; break;
		case '2': scale = 2; break;
		case 'd': spidev = optarg; break;
		case 'g': chip = optarg; break;
		case 'o': pbm = optarg; break;
		default: usage();
		}
	}

	if (!pbm) {
		gpio_init(chip);
		spi_init(spidev, 4000000);
		panel_init();
	}
	fb_clear();

	if (!clear) {
		if (test) {
			draw_test_pattern();
		} else if (optind < argc) {
			int y = 2;
			for (int i = optind; i < argc; i++) {
				draw_text(2, y, argv[i], scale);
				y += FONT_H * scale + 2;
				if (y + FONT_H * scale > LAND_H)
					break;    // no room for another line
			}
		} else {
			usage();
		}
	}

	if (pbm) {
		fb_write_pbm(pbm);
		return 0;
	}
	panel_show();
	if (!keep)
		panel_sleep();
	return 0;
}

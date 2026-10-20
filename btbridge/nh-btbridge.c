// SPDX-License-Identifier: GPL-2.0
/*
 * nh-btbridge — міст між AIDL Bluetooth HAL Android і /dev/vhci ядра Linux.
 *
 * Навіщо: bluebinder (NetHunter/mer-hybris) знає лише HIDL android.hardware.bluetooth@1.0
 * через /dev/hwbinder. Пристрої, що вийшли з Android 14+ (Nothing Phone (3) тощо), мають
 * тільки AIDL android.hardware.bluetooth.IBluetoothHci/default через /dev/binder.
 *
 * Як працює: ініціалізуємо HAL (він вантажить прошивку контролера), створюємо віртуальний
 * HCI-пристрій через /dev/vhci і пересилаємо H4-пакети в обидва боки. Після цього вбудований
 * Bluetooth телефона видно в Linux як hciN (hciconfig, bluetoothctl, Bluetooth Arsenal).
 *
 * Вимога: системний Bluetooth Android має бути ВИМКНЕНИЙ (HAL обслуговує одного клієнта).
 *
 * Інтерфейси (frozen AIDL, hardware/interfaces/bluetooth/aidl/aidl_api/.../1):
 *   IBluetoothHci:          close=1 initialize=2 sendAclData=3 sendHciCommand=4 sendIsoData=5 sendScoData=6
 *   IBluetoothHciCallbacks: aclDataReceived=1 hciEventReceived=2 initializationComplete=3
 *                           isoDataReceived=4 scoDataReceived=5
 */
#include <android/binder_ibinder.h>
#include <android/binder_parcel.h>
#include <android/binder_status.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Платформні API libbinder_ndk, яких немає в заголовках NDK, але вони експортуються на пристрої. */
AIBinder *AServiceManager_waitForService(const char *instance);
bool ABinderProcess_setThreadPoolMaxThreadCount(uint32_t numThreads);
void ABinderProcess_startThreadPool(void);
void AIBinder_markVintfStability(AIBinder *binder);

#define HAL_INSTANCE "android.hardware.bluetooth.IBluetoothHci/default"
#define HAL_DESCRIPTOR "android.hardware.bluetooth.IBluetoothHci"
#define CB_DESCRIPTOR "android.hardware.bluetooth.IBluetoothHciCallbacks"

enum { HAL_CLOSE = FIRST_CALL_TRANSACTION, HAL_INITIALIZE, HAL_SEND_ACL, HAL_SEND_CMD, HAL_SEND_ISO, HAL_SEND_SCO };
enum { CB_ACL = FIRST_CALL_TRANSACTION, CB_EVENT, CB_INIT_COMPLETE, CB_ISO, CB_SCO };

/* Типи H4-пакетів (include/net/bluetooth/hci.h) */
enum { H4_CMD = 0x01, H4_ACL = 0x02, H4_SCO = 0x03, H4_EVENT = 0x04, H4_ISO = 0x05, H4_VENDOR = 0xff };

static const char *status_names[] = { "SUCCESS", "ALREADY_INITIALIZED", "UNABLE_TO_OPEN_INTERFACE",
				      "HARDWARE_INITIALIZATION_ERROR", "UNKNOWN" };

static AIBinder *g_hal;
static int g_vhci = -1;
static pthread_mutex_t g_vhci_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_init_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_init_cond = PTHREAD_COND_INITIALIZER;
static int g_init_status = -1;
static volatile sig_atomic_t g_stop;
static int g_verbose;

#define LOG(fmt, ...) fprintf(stderr, "nh-btbridge: " fmt "\n", ##__VA_ARGS__)

/* ---------- приймання байтових масивів з Parcel ---------- */
struct buf {
	int8_t *data;
	int32_t len;
};

static bool buf_alloc(void *arrayData, int32_t length, int8_t **outBuffer)
{
	struct buf *b = arrayData;
	b->len = length;
	if (length <= 0) {
		*outBuffer = NULL;
		return true;
	}
	b->data = malloc(length);
	*outBuffer = b->data;
	return b->data != NULL;
}

/* Надсилає в ядро пакет з H4-префіксом типу. */
static void vhci_send(uint8_t type, const int8_t *data, int32_t len)
{
	uint8_t pkt[1 + 65536];

	if (len < 0 || len > 65535)
		return;
	pkt[0] = type;
	memcpy(pkt + 1, data, len);
	pthread_mutex_lock(&g_vhci_lock);
	if (g_vhci >= 0 && write(g_vhci, pkt, len + 1) < 0)
		LOG("write to /dev/vhci: %s", strerror(errno));
	pthread_mutex_unlock(&g_vhci_lock);
	if (g_verbose)
		LOG("HAL→hci type=0x%02x len=%d", type, len);
}

/* ---------- об'єкт колбеків, який передаємо HAL ---------- */
static void *cb_on_create(void *args) { return args; }
static void cb_on_destroy(void *userData) { (void)userData; }

static binder_status_t cb_on_transact(AIBinder *binder, transaction_code_t code, const AParcel *in, AParcel *out)
{
	(void)binder;
	struct buf b = { 0 };
	binder_status_t st = STATUS_OK;

	switch (code) {
	case CB_INIT_COMPLETE: {
		int32_t status = -1;
		st = AParcel_readInt32(in, &status);
		pthread_mutex_lock(&g_init_lock);
		g_init_status = status;
		pthread_cond_broadcast(&g_init_cond);
		pthread_mutex_unlock(&g_init_lock);
		break;
	}
	case CB_EVENT:
	case CB_ACL:
	case CB_SCO:
	case CB_ISO:
		st = AParcel_readByteArray(in, &b, buf_alloc);
		if (st == STATUS_OK)
			vhci_send(code == CB_EVENT ? H4_EVENT : code == CB_ACL ? H4_ACL : code == CB_SCO ? H4_SCO : H4_ISO,
				  b.data, b.len);
		free(b.data);
		break;
	default:
		return STATUS_UNKNOWN_TRANSACTION;
	}
	if (st != STATUS_OK)
		return st;
	/* AIDL NDK-backend очікує заголовок статусу у відповіді на не-oneway виклик */
	AStatus *ok = AStatus_newOk();
	st = AParcel_writeStatusHeader(out, ok);
	AStatus_delete(ok);
	return st;
}

/* Клієнтський клас для HAL (onTransact не використовується — це віддалений об'єкт). */
static binder_status_t hal_on_transact(AIBinder *b, transaction_code_t c, const AParcel *i, AParcel *o)
{
	(void)b; (void)c; (void)i; (void)o;
	return STATUS_UNKNOWN_TRANSACTION;
}

/* Виклик методу HAL: arg — масив байтів (або NULL), cb — binder колбеків (або NULL). */
static binder_status_t hal_call(transaction_code_t code, const int8_t *data, int32_t len, AIBinder *cb)
{
	AParcel *in = NULL, *out = NULL;
	binder_status_t st = AIBinder_prepareTransaction(g_hal, &in);

	if (st != STATUS_OK)
		return st;
	if (cb)
		st = AParcel_writeStrongBinder(in, cb);
	else if (data)
		st = AParcel_writeByteArray(in, data, len);
	if (st == STATUS_OK)
		st = AIBinder_transact(g_hal, code, &in, &out, 0);	/* in звільняється всередині */
	else
		AParcel_delete(in);
	if (st == STATUS_OK) {
		AStatus *remote = NULL;
		st = AParcel_readStatusHeader(out, &remote);
		if (st == STATUS_OK && remote && !AStatus_isOk(remote)) {
			LOG("HAL returned error: %s", AStatus_getDescription(remote));
			st = STATUS_FAILED_TRANSACTION;
		}
		if (remote)
			AStatus_delete(remote);
	}
	if (out)
		AParcel_delete(out);
	return st;
}

static void on_hal_died(void *cookie)
{
	(void)cookie;
	LOG("Bluetooth HAL process died - exiting");
	g_stop = 1;
	pthread_mutex_lock(&g_vhci_lock);
	if (g_vhci >= 0) {
		close(g_vhci);
		g_vhci = -1;
	}
	pthread_mutex_unlock(&g_vhci_lock);
	_exit(3);
}

static void on_signal(int sig)
{
	(void)sig;
	g_stop = 1;
}

int main(int argc, char **argv)
{
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-v"))
			g_verbose = 1;
		else {
			fprintf(stderr, "usage: %s [-v]\n", argv[0]);
			return 2;
		}
	}

	struct sigaction sa = { .sa_handler = on_signal };
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	signal(SIGPIPE, SIG_IGN);

	ABinderProcess_setThreadPoolMaxThreadCount(2);
	ABinderProcess_startThreadPool();

	LOG("waiting for service %s", HAL_INSTANCE);
	g_hal = AServiceManager_waitForService(HAL_INSTANCE);
	if (!g_hal) {
		LOG("service not found");
		return 1;
	}
	AIBinder_Class *hal_class = AIBinder_Class_define(HAL_DESCRIPTOR, cb_on_create, cb_on_destroy, hal_on_transact);
	if (!AIBinder_associateClass(g_hal, hal_class)) {
		LOG("service descriptor is not %s", HAL_DESCRIPTOR);
		return 1;
	}
	AIBinder_DeathRecipient *dr = AIBinder_DeathRecipient_new(on_hal_died);
	AIBinder_linkToDeath(g_hal, dr, NULL);

	AIBinder_Class *cb_class = AIBinder_Class_define(CB_DESCRIPTOR, cb_on_create, cb_on_destroy, cb_on_transact);
	AIBinder *cb = AIBinder_new(cb_class, NULL);
	/* HAL @VintfStability: без цього він відмовиться викликати наш об'єкт */
	AIBinder_markVintfStability(cb);

	LOG("initialize()");
	binder_status_t st = hal_call(HAL_INITIALIZE, NULL, 0, cb);
	if (st != STATUS_OK) {
		LOG("initialize() failed: %d", st);
		return 1;
	}

	struct timespec deadline;
	clock_gettime(CLOCK_REALTIME, &deadline);
	deadline.tv_sec += 10;
	pthread_mutex_lock(&g_init_lock);
	while (g_init_status < 0 && !g_stop)
		if (pthread_cond_timedwait(&g_init_cond, &g_init_lock, &deadline) == ETIMEDOUT)
			break;
	int init = g_init_status;
	pthread_mutex_unlock(&g_init_lock);
	if (init != 0) {
		LOG("controller initialization: %s", init < 0 ? "timeout" : init < 5 ? status_names[init] : "?");
		if (init == 1)
			LOG("HAL is busy - turn off Android Bluetooth and Bluetooth scanning (or use: nh-bt start)");
		hal_call(HAL_CLOSE, NULL, 0, NULL);
		return 1;
	}
	LOG("controller ready");

	int fd = open("/dev/vhci", O_RDWR);
	if (fd < 0) {
		LOG("/dev/vhci: %s (is hci_vhci loaded? nh-kmod load)", strerror(errno));
		hal_call(HAL_CLOSE, NULL, 0, NULL);
		return 1;
	}
	/* vendor-пакет: створити HCI-пристрій типу PRIMARY */
	const uint8_t create[2] = { H4_VENDOR, 0x00 };
	if (write(fd, create, sizeof(create)) != sizeof(create)) {
		LOG("creating hci device: %s", strerror(errno));
		close(fd);
		hal_call(HAL_CLOSE, NULL, 0, NULL);
		return 1;
	}
	pthread_mutex_lock(&g_vhci_lock);
	g_vhci = fd;
	pthread_mutex_unlock(&g_vhci_lock);

	uint8_t pkt[1 + 65536];
	while (!g_stop) {
		ssize_t n = read(fd, pkt, sizeof(pkt));
		if (n < 0) {
			if (errno == EINTR)
				continue;
			LOG("read from /dev/vhci: %s", strerror(errno));
			break;
		}
		if (n < 1)
			continue;
		transaction_code_t code = 0;
		switch (pkt[0]) {
		case H4_VENDOR:
			if (n >= 4)
				LOG("created hci%u - check: hciconfig -a / btmgmt info", pkt[2] | (pkt[3] << 8));
			continue;
		case H4_CMD: code = HAL_SEND_CMD; break;
		case H4_ACL: code = HAL_SEND_ACL; break;
		case H4_SCO: code = HAL_SEND_SCO; break;
		case H4_ISO: code = HAL_SEND_ISO; break;
		default:
			LOG("unknown packet type 0x%02x", pkt[0]);
			continue;
		}
		if (g_verbose)
			LOG("hci→HAL type=0x%02x len=%zd", pkt[0], n - 1);
		st = hal_call(code, (const int8_t *)pkt + 1, (int32_t)(n - 1), NULL);
		if (st != STATUS_OK)
			LOG("send to HAL (type 0x%02x): %d", pkt[0], st);
	}

	LOG("stopping: removing hci device and closing HAL");
	pthread_mutex_lock(&g_vhci_lock);
	close(g_vhci);
	g_vhci = -1;
	pthread_mutex_unlock(&g_vhci_lock);
	hal_call(HAL_CLOSE, NULL, 0, NULL);
	return 0;
}

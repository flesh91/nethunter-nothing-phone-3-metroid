// SPDX-License-Identifier: GPL-2.0
/*
 * Заглушки файлових API для out-of-tree Realtek-драйверів на GKI.
 * filp_open/kernel_read/kernel_write не входять до KMI (abi_symbollist), тож
 * модуль з ними не завантажиться. Драйвери читають файли лише для опційних
 * функцій (PHY-таблиці/MAC з файлу) і коректно обробляють помилку.
 */
#include <linux/fs.h>
#include <linux/err.h>

struct file *filp_open(const char *filename, int flags, umode_t mode)
{
	return ERR_PTR(-EOPNOTSUPP);
}

ssize_t kernel_read(struct file *file, void *buf, size_t count, loff_t *pos)
{
	return -EOPNOTSUPP;
}

ssize_t kernel_write(struct file *file, const void *buf, size_t count, loff_t *pos)
{
	return -EOPNOTSUPP;
}

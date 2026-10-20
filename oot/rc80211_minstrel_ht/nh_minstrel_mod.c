// SPDX-License-Identifier: GPL-2.0-only
/*
 * Обгортка: робить вбудований у mac80211 алгоритм minstrel_ht окремим модулем.
 * Вендорський mac80211 на Nothing Phone (3) зібраний з CONFIG_MAC80211_RC_MINSTREL=n,
 * тож без цього модуля USB-адаптери без апаратного rate control не стартують.
 */
#include <linux/module.h>
#include "rate.h"

int rc80211_minstrel_init(void);
void rc80211_minstrel_exit(void);

static int __init nh_minstrel_init(void)
{
	return rc80211_minstrel_init();
}

static void __exit nh_minstrel_exit(void)
{
	rc80211_minstrel_exit();
}

module_init(nh_minstrel_init);
module_exit(nh_minstrel_exit);
MODULE_DESCRIPTION("minstrel_ht TX rate control as a module (for vendor mac80211 without RC)");
MODULE_LICENSE("GPL");

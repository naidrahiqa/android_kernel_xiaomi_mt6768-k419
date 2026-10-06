// SPDX-License-Identifier: GPL-2.0-only

#ifndef ENCORE_FAS_STATS_H
#define ENCORE_FAS_STATS_H

#include <linux/math64.h>
#include <linux/string.h>
#include <linux/types.h>

#include "uapi/encore_fas_uapi.h"

/**
 * @brief Histogram of frame intervals.
 *
 * The frame path adds one interval per call. It multiplies by a reciprocal
 * that fas_hist_init() computes once, so it does not divide.
 */
struct fas_hist {
	/** 2^FAS_HIST_SHIFT divided by the bin width in ticks. */
	u64 recip;
	/** Longest interval that is still counted by its own bin, in ticks. */
	u64 clamp;
	/** Count of intervals since the last clear. */
	u64 frames;
	/** Interval counts. The last bin holds all longer intervals. */
	u32 bin[FAS_HIST_BINS];
};

/* Largest product: 2^27 ticks times 2^30 at 19.2 MHz or 2^24 at 1 GHz. */
#define FAS_HIST_SHIFT 44

/**
 * @brief Sets bin width and clears all counts.
 *
 * @param hs Histogram.
 * @param freq Timer counter frequency in Hz.
 */
static inline void fas_hist_init(struct fas_hist *hs, u64 freq)
{
	u64 bin_ticks = div_u64(freq * FAS_HIST_BIN_NS, 1000000000U);

	memset(hs, 0, sizeof(*hs));
	if (!bin_ticks)
		bin_ticks = 1;
	hs->recip = div64_u64(1ULL << FAS_HIST_SHIFT, bin_ticks);
	hs->clamp = bin_ticks * FAS_HIST_BINS;
}

/**
 * @brief Clears all counts and keeps the bin width.
 *
 * @param hs Histogram.
 */
static inline void fas_hist_clear(struct fas_hist *hs)
{
	memset(hs->bin, 0, sizeof(hs->bin));
	hs->frames = 0;
}

/**
 * @brief Adds one frame interval.
 *
 * Clamping first keeps the product below 2^64 for any interval.
 *
 * @param hs Histogram.
 * @param delta Frame interval in ticks.
 */
static __always_inline void fas_hist_add(struct fas_hist *hs, u64 delta)
{
	u64 idx;

	if (delta > hs->clamp)
		delta = hs->clamp;
	idx = (delta * hs->recip) >> FAS_HIST_SHIFT;
	if (idx >= FAS_HIST_BINS)
		idx = FAS_HIST_BINS - 1;
	hs->bin[idx]++;
	hs->frames++;
}

#endif

---
id: 0015
title: DroidSpaces container support dipulihkan penuh (USER_NS + cgroup net + firewall) sesuai requirements v6.6.0
status: fixed
severity: medium
area: config
opened: 2026-10-14
updated: 2026-10-14
fix_commit: "746f238a9f15"
verified_on: ""
tags: [droidspaces, user-ns, cgroup, defconfig, container, netfilter]
related: []
---

## Issue

Dukungan container DroidSpaces sengaja dibuang 29 Sep 2026
(`71148109aa08` drop `USER_NS` + `CGROUP_NET_PRIO`/`CGROUP_NET_CLASSID`,
`9063880b9d3d` bersih-bersih sisa blok) dengan alasan RAM 6GB. Tanpa
`USER_NS` aplikasi container tidak bisa membuat user namespace —
DroidSpaces jadi **non-fungsional**.

Permintaan owner (14 Okt 2026): restore **penuh** sesuai requirements
Droidspaces v6.6.0 (non-GKI 4.19) di
<https://github.com/ravindu644/Droidspaces-OSS>
(`Documentation/Kernel-Configuration.md`), termasuk semua blok opsional
sampai firewall (NAT66 + macvlan + UFW/fail2ban). Alasan drop RAM
dibatalkan atas persetujuan owner.

## Evidence

- Panduan v6.6.0 mewajibkan: IPC, namespace (incl. `USER_NS`),
  seccomp, cgroups (incl. net prio/classid, `CFS_BANDWIDTH`), overlay,
  tmpfs xattr/acl, firmware loader, network isolation (veth/bridge/NAT),
  IPv6 NAT (NAT66), macvlan, `ANDROID_PARANOID_NETWORK=n`.
- Patch wajib non-GKI tersedia di repo DroidSpaces:
  `01.patch` (xt_qtaguid) dan `02.patch` (cgroup prefix).
- State defconfig sebelum fix: `USER_NS`, `CGROUP_NET_PRIO`,
  `CGROUP_NET_CLASSID` = not set (lihat `71148109aa08`).

## Root cause

Bukan bug kernel — feature drop sadar yang dibatalkan kembali. Yang
perlu dicatat adalah **adaptasi nama simbol** karena panduan ditulis
untuk kernel non-4.19:

| Panduan (baru) | Kenyataan di 4.19.325 |
|---|---|
| `NETFILTER_XT_TARGET_MASQUERADE` | belum ada → pakai `IP_NF_TARGET_MASQUERADE` + `IP6_NF_TARGET_MASQUERADE` |
| `NETFILTER_XT_TARGET_REJECT` | belum ada → pakai `IP_NF_TARGET_REJECT` + `IP6_NF_TARGET_REJECT` |
| `NF_CONNTRACK_NETLINK` | simbol aslinya `NF_CT_NETLINK` |
| `IP_NF_TARGET_ULOG` | sudah dihapus dari tree → gugur |
| `FW_LOADER_COMPRESS` | fitur kernel ≥5.3 → gugur |
| `ANDROID_PARANOID_NETWORK` | simbol tidak ada → gugur |
| `NF_CONNTRACK_IPV4`/`IPV6` | split conntrack sudah dihapus dari tree → gugur |

## Fix

1. `kernel/cgroup/cgroup.c` (`8fcdc00394d0`) — patch wajib 02 dari
   DroidSpaces: buat symlink berprefiks (`ss.name.`) untuk cgroup file
   pada root `CGRP_ROOT_NOPREFIX` (`cgroup_add_file`), supaya userland
   container (LXC/distro) tetap menemukan `cpuacct.usage` dkk. di
   hierarchy hybrid/v1. **Patch 01 (xt_qtaguid) no-op**:
   `net/netfilter/xt_qtaguid.c` tidak ada di tree kita (Android baru
   pakai eBPF traffic stats) — panic yang dicegah patch itu mustahil
   terjadi.
2. `arch/arm64/configs/selene_defconfig` — blok DroidSpaces v6.6.0
   penuh (~100 baris): namespace + `USER_NS`, seccomp, cgroups
   (net prio/classid, `CFS_BANDWIDTH`, freezer, cpuacct), overlay,
   firmware loader, network isolation NAT, NAT66, macvlan, dan blok
   UFW/fail2ban (xt matches, `IP_SET`, NFLOG/LOG/REJECT).

## Verification

- [x] `make O=out ARCH=arm64 selene_defconfig` → **semua simbol blok
      lolos** ke `out/.config` (tidak ada yang silently dropped)
- [x] Diff `.config` HEAD vs baru: **10 baris berubah = semua flip
      n→y yang diinginkan, 0 baris hilang tak terduga** (regresi
      `XT_MATCH_ADDRTYPE` sempat terjadi karena salah hapus —
      sudah dikembalikan)
- [x] Konfig lain tetap utuh: `MQ_DEADLINE_DEFAULT=y`,
      floor 1270000/1443000, `KSU=y`, `NOMOUNT=y`
- [ ] flash build berikutnya → `unshare -U id` (userns jalan),
      `/proc/self/ns/` ada `user`, container app bisa start
- [ ] jalankan DroidSpaces + UFW di dalam container → trafik lolos

## Regression test

Kalau RAM 6GB kewalahan lagi karena container: matikan kembali cuma
`USER_NS` (satu baris) — app container otomatis berhenti membuat
namespace dan berhenti makan memori; blok netfilter/cgroup lain aman
dibiarkan (konsumsinya kecil saat tidak dipakai).

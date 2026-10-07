# Issue Tracker

Satu issue = satu file. Format & alur dikelola lewat skill
`.opencode/skills/issue-tracker/SKILL.md` (perintah: `catat issue`,
`list issue`, `fix issue`, `verified issue`).

Berkas `.md` tidak memicu build CI (`paths-ignore: '**.md'` di
`.github/workflows/build.yml`).

## Nomor & nama file

`NNNN-<slug>.md` — 4 digit urut + slug kecil pakai `-`.
Slug = inti masalah, bukan gejala (`0001-adios-reboot.md`, bukan
`0001-hp-mati-tiba-tiba.md`).

## Status

| Status | Arti | Keluar lewat |
|---|---|---|
| `open` | baru dicatat, belum didiagnosis | `diagnose issue N <root cause>` |
| `diagnose` → `diagnosed` | root cause ketemu, fix belum ada / belum di-commit | `fix issue N <sha>` |
| `fixed` | kode sudah di-commit, **belum dibuktikan di device** | `verified issue N <bukti>` |
| `verified` | sudah dites di hardware dan beres — **tutup resmi** | — |
| `wontfix` | sengaja tidak diperbaiki (alasan wajib diisi) | `close issue N wontfix <alasan>` |
| `regressed` | pernah `verified`, kembali muncul | `reopen issue N <bukti>` |

`regressed` → `diagnosed` → `fixed` → `verified` lagi. Jangan pernah menghapus
file issue yang sudah `verified` — riwayatnya jadi bukti kalau bug itu pernah
balik.

## Posisi dalam alur kerja

1. Bug kecatat sebagai issue (`open`).
2. Kode fix di-commit → issue `fixed`, `fix_commit` diisi.
3. Di-test di HP → `verified` + `verified_on` (uname -r build yang dites).
4. Issue yang ternyata berulang dan gampang salah → tambahkan 1 baris di
   tabel **Known Gotchas** `AGENTS.md`, lengkap dengan Issue ID-nya.

Jangan menaruh detail debugging di `AGENTS.md` — cukup 1 baris + Issue ID.
Detail, bukti dmesg, dan alur penalaran tinggal di file issue masing-masing.

## Index

```bash
for f in docs/issues/[0-9]*.md; do
  printf '%s  %-10s %s\n' "${f##*/}" "$(sed -n 's/^status: //p' "$f")" \
    "$(sed -n 's/^title: //p' "$f")"
done | sort
```

#!/usr/bin/env bash
# Hearth Droid: takes a TrebleDroid GSI (system.img) and builds Hearth into it.
#   - Hearth for Android as a built-in (priv-app) app, with its native libraries next to it
#   - the privileged permissions it asks for, allowed (build/gen-privapp.py), so Android always finishes starting
#   - Hearth's boot animation
#   - ro.hearth.droid.* properties (nothing of Android's own is changed)
# Every file added gets the same SELinux label and owner as the folder it goes in; the build stops if one doesn't.
#
# usage (as root): remix.sh <base system.img> <hearth.apk> <bootanimation.zip> <aapt2> <out.img> <workdir> <base tag> <build id>
set -euo pipefail

base=$1 apk=$2 boot=$3 aapt2=$4 out=$5 work=$6 base_tag=$7 build_id=$8
here=$(cd "$(dirname "$0")" && pwd)
err() { echo "::error title=Remix::$*"; exit 1; }

mkdir -p "$work"
rm -f "$out"

# A sparse image (magic ED26FF3A) is made raw first.
if [ "$(head -c4 "$base" | od -An -tx1 | tr -d ' \n')" = "3aff26ed" ]; then
  simg2img "$base" "$work/base.raw"
  base="$work/base.raw"
fi

kind=$(blkid -o value -s TYPE "$base" 2>/dev/null || true)
echo "::notice title=Base image::$(basename "$base"): ${kind:-unknown} filesystem, $(du -h --apparent-size "$base" | cut -f1)"

# Copies the SELinux label (as raw hex, exactly) and owner of $1 onto $2.
label_like() {
  local ref=$1 f=$2 hex
  hex=$(getfattr --absolute-names -e hex -n security.selinux "$ref" 2>/dev/null | sed -n 's/^security.selinux=//p')
  [ -n "$hex" ] || err "$ref has no SELinux label to copy"
  setfattr -h -n security.selinux -v "$hex" "$f"
  chown -h --reference="$ref" "$f"
}

inject() {
  local root=$1 sys
  if [ -d "$root/system/priv-app" ]; then sys=$root/system; else sys=$root; fi
  [ -f "$sys/framework/framework-res.apk" ] || err "no framework/framework-res.apk in the image: not a system image?"
  [ -f "$sys/build.prop" ] || err "no build.prop in the image"

  local app=$sys/priv-app/HearthLauncher
  [ -e "$app" ] && err "priv-app/HearthLauncher already exists in the base"
  mkdir -p "$app"
  install -m 0644 "$apk" "$app/HearthLauncher.apk"

  # Native libraries: Android doesn't unpack them for an app built into /system, so they go in lib/<abi>/.
  local tmp; tmp=$(mktemp -d)
  unzip -q -o "$apk" 'lib/*' -d "$tmp" 2>/dev/null || true
  for pair in arm64-v8a:arm64 armeabi-v7a:arm x86_64:x86_64 x86:x86; do
    local abi=${pair%%:*} dir=${pair##*:}
    if compgen -G "$tmp/lib/$abi/*.so" >/dev/null; then
      mkdir -p "$app/lib/$dir"
      install -m 0644 "$tmp/lib/$abi/"*.so "$app/lib/$dir/"
    fi
  done
  rm -rf "$tmp"

  # Privileged permissions it asks for, allowed.
  python3 "$here/gen-privapp.py" "$aapt2" "$apk" "$sys/framework/framework-res.apk" \
    "$sys/etc/permissions/privapp-permissions-hearth.xml"
  chmod 0644 "$sys/etc/permissions/privapp-permissions-hearth.xml"

  # Boot animation: where this Android looks for it (system/media, and product/media when the base has one there).
  local new_media=0
  [ -d "$sys/media" ] || { mkdir -p "$sys/media"; new_media=1; }
  install -m 0644 "$boot" "$sys/media/bootanimation.zip"
  if [ -f "$sys/product/media/bootanimation.zip" ]; then
    install -m 0644 "$boot" "$sys/product/media/bootanimation.zip"
  fi

  # Hearth's own properties, added at the end; Android's are left as they are.
  printf '\n# Hearth Droid\nro.hearth.droid=1\nro.hearth.droid.base=%s\nro.hearth.droid.build=%s\n' \
    "$base_tag" "$build_id" >> "$sys/build.prop"

  # Labels: everything new takes its parent folder's label and owner.
  local f
  label_like "$sys/priv-app" "$app"
  while IFS= read -r -d '' f; do label_like "$(dirname "$f")" "$f"; done < <(find "$app" -mindepth 1 -print0)
  [ "$new_media" = 1 ] && label_like "$sys/etc" "$sys/media"
  for f in "$sys/etc/permissions/privapp-permissions-hearth.xml" "$sys/media/bootanimation.zip"; do
    label_like "$(dirname "$f")" "$f"
  done

  # Check: every file we added carries a label, and it's the same as its folder's.
  local bad=0
  while IFS= read -r -d '' f; do
    local a b
    a=$(getfattr --absolute-names -e hex -n security.selinux "$f" 2>/dev/null | sed -n 's/^security.selinux=//p')
    b=$(getfattr --absolute-names -e hex -n security.selinux "$(dirname "$f")" 2>/dev/null | sed -n 's/^security.selinux=//p')
    if [ -z "$a" ] || [ "$a" != "$b" ]; then echo "::error title=SELinux label::$f"; bad=1; fi
  done < <(find "$app" "$sys/etc/permissions/privapp-permissions-hearth.xml" "$sys/media/bootanimation.zip" -mindepth 0 -print0)
  [ "$bad" = 0 ] || err "some added files don't carry the right SELinux label (see above)"

  local ctx; ctx=$(getfattr --absolute-names -n security.selinux --only-values "$app/HearthLauncher.apk" | tr -d '\0')
  echo "::notice title=Hearth added::priv-app/HearthLauncher ($(du -sh "$app" | cut -f1), label $ctx), boot animation, privapp permissions"
}

case "$kind" in
  ext4)
    cp --sparse=always "$base" "$out"
    # Android's ext4 images often share blocks between files (read-only); unshare them so it can be changed.
    if tune2fs -l "$out" | grep -q shared_blocks; then
      e2fsck -fy -E unshare_blocks "$out" || [ $? -le 1 ] || err "e2fsck couldn't unshare the image's blocks"
    fi
    truncate -s +768M "$out"
    e2fsck -fy "$out" >/dev/null || [ $? -le 1 ] || err "e2fsck found errors in the base image"
    resize2fs "$out" >/dev/null
    mkdir -p "$work/mnt"
    mount -o loop,rw "$out" "$work/mnt"
    trap 'umount "$work/mnt" 2>/dev/null || true' EXIT
    inject "$work/mnt"
    sync
    umount "$work/mnt"; trap - EXIT
    e2fsck -fy "$out" >/dev/null || [ $? -le 1 ] || err "e2fsck found errors after adding Hearth"
    resize2fs -M "$out" >/dev/null
    # A little room, then the file cut to the filesystem's size.
    bc=$(dumpe2fs -h "$out" 2>/dev/null | sed -n 's/^Block count: *//p')
    bs=$(dumpe2fs -h "$out" 2>/dev/null | sed -n 's/^Block size: *//p')
    resize2fs "$out" $(( bc + 16 * 1024 * 1024 / bs )) >/dev/null
    truncate -s $(( (bc + 16 * 1024 * 1024 / bs) * bs )) "$out"
    e2fsck -fn "$out" >/dev/null || err "the finished image doesn't pass e2fsck"
    ;;
  erofs)
    mkdir -p "$work/ro" "$work/tree"
    mount -t erofs -o loop,ro "$base" "$work/ro"
    cp -a "$work/ro/." "$work/tree/"
    umount "$work/ro"
    inject "$work/tree"
    mkfs.erofs -zlz4hc "$out" "$work/tree" >/dev/null
    fsck.erofs "$out" >/dev/null || err "the finished image doesn't pass fsck.erofs"
    ;;
  *)
    err "the base image's filesystem is '${kind:-unknown}', not ext4 or erofs"
    ;;
esac

echo "::notice title=Hearth Droid image::$(du -h --apparent-size "$out" | cut -f1) ($kind)"

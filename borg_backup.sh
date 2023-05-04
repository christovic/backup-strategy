#!/bin/sh
info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
# Run checks to ensure we have the necessary environment variables
if [ -z "$BORG_REPO" ] || [ -z "$BORG_PASSPHRASE" ] || [ -z "$PATTERN_LIST_LOCATION" ]; then
    if [ -z "$BORG_REPO" ]; then
        info "Missing BORG_REPO environment variable"
    fi
    if [ -z "$BORG_PASSPHRASE" ]; then
        info "Missing BORG_PASSPHRASE environment variable"
    fi
    if [ -z "$PATTERN_LIST_LOCATION" ]; then
        info "Missing PATTERN_LIST_LOCATION environment variable"
    fi
    exit 1
fi

# Create snapshots if the BTRFS_SNAP_LOCATION variable is set
if [ -n "$BTRFS_SNAP_LOCATION" ]; then
    btrfs subvolume snapshot /mnt/btr_pool/@rootfs "$BTRFS_SNAP_LOCATION"
    btrfs subvolume snapshot /mnt/btr_pool/@home "$BTRFS_SNAP_LOCATION"
    cd "$BTRFS_SNAP_LOCATION" || exit
fi

info "We are in $(pwd)"

# some helpers and error handling:
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

info "Starting backup"

# Backup the most important directories into an archive named after
# the machine this script is currently running on:
info "$BORG_REPO"
borg create                         \
    --verbose                       \
    --filter AME                    \
    --list                          \
    --stats                         \
    --show-rc                       \
    --compression lz4               \
    --exclude-caches                \
    $EXTRA_OPTIONS              \
    --patterns-from $PATTERN_LIST_LOCATION     \
    ::'{hostname}-{now}'            \

backup_exit=$?

info "Pruning repository"

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

borg prune                          \
    --list                          \
    --glob-archives '{hostname}-*'  \
    --show-rc                       \
    --keep-daily    7               \
    --keep-weekly   4               \
    --keep-monthly  6

prune_exit=$?

# actually free repo disk space by compacting segments

info "Compacting repository"

borg compact

compact_exit=$?

# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

if [ ${global_exit} -eq 0 ]; then
    message="${0##*/}: Backup and Prune finished successfully"
    info "${message}"
elif [ ${global_exit} -eq 1 ]; then
    message="$(hostname) ${0##*/}: Backup and/or Prune finished with warnings"
    info "${message}"
    telegram-send "${message}"
else
    message="$(hostname) ${0##*/}: Backup and/or Prune finished with errors"
    info "${message}"
    telegram-send "${message}"
fi

if [ -n "$BTRFS_SNAP_LOCATION" ]; then
    btrfs subvolume delete  "$BTRFS_SNAP_LOCATION"/@rootfs
    btrfs subvolume delete  "$BTRFS_SNAP_LOCATION"/@home
fi
exit ${global_exit}
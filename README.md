# getMoreRam.sh

An interactive shell script to **resize or create swap partitions** on Linux systems.  
⚠️ **Warning:** This script modifies disk partitions and filesystems. Misuse can destroy data. Always back up before running.

---

## Features
- Interactive disk/partition selection.
- Creates a swap partition if free space exists.
- If no free space, offers to shrink ext2/3/4 partitions (never XFS).
- Runs filesystem checks before shrinking.
- Formats and enables swap.
- Prints `/etc/fstab` entry for persistence.

---

## Usage
```bash
sudo ./getMoreRam.sh

import sys
import lief
import shutil

def main():
    if len(sys.argv) != 4:
        print("usage: sign.py <input elf> <key> <output elf>")
        return 1

    elf = lief.ELF.parse(sys.argv[1])
    # Create a new section to hold the key
    key_sect = lief.ELF.Section(".ot.key", lief.ELF.Section.TYPE.NOTE)
    key_sect.content = list("key is: {}".format(sys.argv[2]).encode("utf-8"))
    elf.add(key_sect, loaded = False)
    elf.write(sys.argv[3])
    return 0

sys.exit(main())
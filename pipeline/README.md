# How to run:

```bash
bazelisk build //example:ot_binary
objdump -s -j .ot.key $(bazelisk cquery --output=files //example:ot_binary)
```

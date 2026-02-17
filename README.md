# ESK Builder Environment Variables

- bool: accept 1/0, y/n, yes/no, t/f, true/false, on/off
- int: number

| **Name**      | **Use**                                | **Type** |
| ------------- | -------------------------------------- | -------- |
| KSU           | Include KernelSU                       | bool     |
| SUSFS         | Include SUSFS                          | bool     |
| LXC           | Include LXC                            | bool     |
| JOBS          | Make jobs                              | int      |
| RESET_SOURCES | Reset source directory (kernel, clang) | bool     |
| TG_NOTIFY     | Telegram notify                        | bool     |
